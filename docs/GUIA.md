# Guía anotada del proyecto

Este repo no es un proyecto real: es un **laboratorio para entender dos cosas**
que suelen enseñarse por separado y que en la práctica van juntas:

1. Una **arquitectura por capas** (routers → services → repositories).
2. Un **pipeline de CI/CD** que verifica esas capas automáticamente.

La guía va en el mismo orden en que nació el proyecto. Cada sección te dice
**qué archivo abrir** y **qué comando correr** para comprobarlo tú mismo.

---

## Antes de empezar: deja el proyecto corriendo

```bash
uv sync                  # instala dependencias desde uv.lock
uv run pytest -q         # 12 tests deberían pasar
uv run uvicorn app.main:app --reload
```

Con el servidor arriba, abre <http://127.0.0.1:8000/docs>. Esa página la genera
FastAPI sola, leyendo los tipos de los endpoints. Vas a poder probar la API
desde el navegador sin escribir una línea de cliente.

> Si no tienes `uv`: <https://docs.astral.sh/uv/getting-started/installation/>

---

## Paso 0 — El script que creó todo esto

Archivo: [`new-api.sh`](./new-api.sh)

Este proyecto no se escribió a mano: lo generó ese script de una pasada. Es un
**andamio** (*scaffold*): se usa **una sola vez**, el día que nace el proyecto,
y después no se vuelve a tocar. Todo cambio posterior se hace editando archivos.

Lo que hace, en orden:

| # | Qué hace | Por qué |
|---|---|---|
| 1 | `set -euo pipefail` | Corta al primer error, en vez de seguir y commitear algo roto |
| 2 | Crea el árbol de carpetas | Estructura por capas desde el minuto cero |
| 3 | Escribe `pyproject.toml` | Un solo archivo de config para todas las herramientas |
| 4 | `uv add` de dependencias | Genera `uv.lock` con versiones exactas |
| 5 | Escribe el código de ejemplo | Un recurso `items` completo, como plantilla a copiar |
| 6 | Escribe el workflow de CI | El pipeline ya existe antes del primer commit |
| 7 | Corre ruff + mypy + pytest | **Verifica antes de commitear**: si algo falla, el script muere |
| 8 | `git init` + primer commit | Historial limpio desde el inicio |
| 9 | `gh repo create --push` | Crea el repo en GitHub y sube todo |

El orden del paso 7 es deliberado: las verificaciones van **antes** del commit.
Gracias a `set -e`, nunca vas a terminar con un repo cuyo primer commit esté roto.

Para reusarlo en un proyecto nuevo:

```bash
bash new-api.sh mi-proyecto-nuevo
```

Y cuando descubras que siempre agregas lo mismo (logging, SQLAlchemy, CORS),
**edita el script**. Ahí está la ganancia real: tus proyectos futuros nacen
con tus convenciones ya puestas.

---

## Paso 1 — Por qué el código vive en `src/`

```
src/app/...      ← el código
tests/...        ← los tests
```

Poner el paquete en `src/app/` en vez de `app/` en la raíz obliga a que el
paquete **se instale** para poder importarse. ¿Por qué querrías eso?

Con el layout plano, cuando corres `pytest` desde la raíz, Python encuentra
`app/` por accidente (está en el directorio actual) y tus tests prueban los
archivos sueltos. Con `src/`, estás probando **lo mismo que se va a instalar
en producción**. Si en el `Dockerfile` te olvidas de copiar un archivo, el
test falla en CI en vez de explotar en el deploy.

Lo que lo hace funcionar son estas líneas de [`pyproject.toml`](./pyproject.toml):

```toml
[tool.hatch.build.targets.wheel]
packages = ["src/app"]
```

**Compruébalo:** `uv run python -c "import app; print(app.__file__)"`

---

## Paso 2 — Las capas, de abajo hacia arriba

La regla única: **las dependencias apuntan en una sola dirección.**

```
  HTTP
   │
   ▼
api/routers/users.py ──► services/user_service.py ──► repositories/user_repository.py
   │                           │                              │
   │ traduce errores           │ lógica de negocio            │ acceso a datos
   │ a códigos HTTP            │ (no sabe de HTTP ni SQL)      │ (detrás de un Protocol)
   ▼                           ▼                              ▼
         schemas/user.py  ·  modelos de entrada y salida (Pydantic)
```

Nada apunta hacia arriba. El service no sabe que existe HTTP; el repository no
sabe que existe un service.

### 2.1 — `schemas/` : la forma de los datos

Archivo: [`src/app/schemas/user.py`](./src/app/schemas/user.py)

Modelos Pydantic. Definen qué entra y qué sale por HTTP. Pydantic valida en
runtime y FastAPI los usa para generar `/docs` sola.

**Compruébalo:** manda un email inválido y mira el 422 que responde sin que
nadie lo haya programado:

```bash
curl -i -X POST localhost:8000/users \
  -H "Content-Type: application/json" \
  -d '{"email":"no-es-un-email","full_name":"X"}'
```

### 2.2 — `repositories/` : el acceso a datos

Archivo: [`src/app/repositories/user_repository.py`](./src/app/repositories/user_repository.py)

Lo importante es el `Protocol`:

```python
class UserRepository(Protocol):
    def add(self, data: UserCreate) -> UserRead: ...
    def get(self, user_id: int) -> UserRead | None: ...
    def get_by_email(self, email: str) -> UserRead | None: ...
```

Un `Protocol` es una **interfaz estructural**: define qué métodos debe tener
algo para calificar como repositorio, pero nadie tiene que heredar de él. Si
tu clase tiene esos tres métodos con esas firmas, mypy la acepta. Es el *duck
typing* de Python, pero verificado estáticamente.

Por eso `InMemoryUserRepository` no hereda de nada y aun así encaja.

### 2.3 — `services/` : la lógica de negocio

Archivo: [`src/app/services/user_service.py`](./src/app/services/user_service.py)

Acá viven las reglas. Mira la del email único:

```python
def register(self, data: UserCreate) -> UserRead:
    if self._repo.get_by_email(data.email) is not None:
        raise EmailAlreadyExistsError(data.email)
    return self._repo.add(data)
```

Dos decisiones que vale la pena notar:

**Lanza `EmailAlreadyExistsError`, no `HTTPException`.** El negocio no debe
saber que existe el protocolo HTTP. Si mañana registras usuarios desde un
script de importación o desde una tarea en segundo plano, la regla se respeta
igual.

**Recibe el repositorio, no lo crea:**

```python
def __init__(self, repo: UserRepository) -> None:
    self._repo = repo
```

Eso es **inyección de dependencias**. Si el service hiciera
`self._repo = SqlAlchemyUserRepository()` adentro, quedaría casado con Postgres
para siempre y no podrías testearlo sin levantar una base de datos.

### 2.4 — `api/routers/` : la capa delgada de arriba

Archivo: [`src/app/api/routers/users.py`](./src/app/api/routers/users.py)

Su único trabajo: validar entrada, llamar al service, traducir errores de
dominio a códigos HTTP.

```python
except EmailAlreadyExistsError:
    raise HTTPException(status_code=409, detail="Email already registered") from None
```

Y la inyección por el lado de FastAPI:

```python
ServiceDep = Annotated[UserService, Depends(get_user_service)]
```

`Depends` ejecuta `get_user_service()` en cada request y pasa el resultado al
endpoint. Guardarlo en una variable evita repetir esa firma larga en cada
endpoint.

**Compruébalo:** el mismo email dos veces responde 201 y después 409:

```bash
curl -i -X POST localhost:8000/users -H "Content-Type: application/json" -d '{"email":"a@b.cl","full_name":"A"}'
curl -i -X POST localhost:8000/users -H "Content-Type: application/json" -d '{"email":"a@b.cl","full_name":"A"}'
```

### 2.5 — `api/deps.py` : el único lugar con cableado

Archivo: [`src/app/api/deps.py`](./src/app/api/deps.py)

Acá se decide **qué repositorio concreto** recibe cada service. Es el único
archivo que cambias cuando pasas de memoria a Postgres:

```python
def get_user_service() -> UserService:
    return UserService(_user_repo)  # ← aquí cambiarías la implementación
```

### 2.6 — `main.py` : la fábrica de la app

Archivo: [`src/app/main.py`](./src/app/main.py)

Usa una función `create_app()` en vez de crear el `app` suelto. Eso se llama
*application factory* y permite armar instancias con configuración distinta en
los tests.

---

## Paso 3 — Los tests, y por qué están en dos carpetas

### `tests/unit/` — reglas de negocio

Archivo: [`tests/unit/test_user_service.py`](./tests/unit/test_user_service.py)

Prueban el service con el repositorio en memoria. Sin red, sin base de datos,
en milisegundos. Cuando uno falla, sabes exactamente qué regla se rompió.

Acá se paga la inyección de dependencias:

```python
def make_service() -> UserService:
    return UserService(InMemoryUserRepository())
```

### `tests/integration/` — el cableado completo

Archivo: [`tests/integration/test_users_api.py`](./tests/integration/test_users_api.py)

Levantan la app entera con `TestClient` y pegan a los endpoints de verdad.
Verifican lo que los unitarios no pueden ver: que el router esté registrado,
que los status codes sean los correctos, que la serialización funcione.

**Compruébalo:**

```bash
uv run pytest tests/unit -q          # rápidos, mientras programas
uv run pytest -q                     # todo
uv run pytest --cov=app --cov-report=term-missing   # con cobertura
```

---

## Paso 4 — El CI/CD, pieza por pieza

Hay **tres momentos** donde se verifica el código, y no se superponen:
cada uno atrapa errores distintos.

| Momento | Qué corre | Dónde | Automático |
|---|---|---|---|
| Mientras programas | lo que tú quieras | tu máquina | no |
| `git commit` | lint + formato | tu máquina | **sí** |
| `git push` / abrir PR | lint + formato + tipos + tests + Docker | GitHub | **sí** |

### 4.1 — pre-commit (en tu máquina, al commitear)

Archivo: [`.pre-commit-config.yaml`](./.pre-commit-config.yaml)

Instala un *git hook*: un script que git ejecuta automáticamente **antes** de
guardar un commit. **No crea commits ni cambia de rama** — solo intercepta.

Qué pasa al hacer `git commit`:

1. Git se detiene antes de guardar nada.
2. Corre ruff sobre los archivos que estás commiteando.
3. Si todo pasa → el commit se guarda. Ni te enteras.
4. Si algo falla → el commit **se aborta**. No se guarda nada.

El detalle que confunde la primera vez: ruff corre con `--fix`, así que muchas
veces **arregla el problema solo**. Pero como modificó los archivos después de
tu `git add`, el commit igual se cancela:

```
ruff.....................................Failed
- files were modified by this hook
```

Eso no es un error tuyo. Significa "te arreglé unas cosas, revísalas y
commitea de nuevo":

```bash
git add .
git commit -m "..."   # ahora sí pasa
```

El efecto neto: **es imposible commitear código mal formateado**, aunque se te
olvide.

Deliberadamente **no corre los tests**. Si el hook tardara 30 segundos,
terminarías usando `git commit --no-verify` para saltártelo. Mejor que sea
instantáneo.

Para instalarlo en un clon nuevo: `uv run pre-commit install`

### 4.2 — GitHub Actions (en los servidores de GitHub)

Archivo: [`.github/workflows/ci.yml`](./.github/workflows/ci.yml)

```yaml
on:
  push:
    branches: [main]
  pull_request:
```

Corre en cada **PR** (para que nada roto llegue a `main`) y en cada **push a
main** (para detectar problemas del merge).

> **Ojo:** `git pull` **no dispara nada**. Pull es traer cambios *desde*
> GitHub *hacia* tu máquina; es una operación local y GitHub ni se entera. Lo
> que dispara el CI es `git push` o abrir un *Pull Request* (que es otra cosa:
> una solicitud de fusionar tu rama en `main`, y es una función de GitHub, no
> de git).

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

Si subes tres commits seguidos, cancela las corridas viejas y deja solo la
última. Ahorra minutos de runner y te da feedback más rápido.

El orden de los pasos no es casual — van **de lo más barato a lo más caro**:

```yaml
- run: uv sync --locked              # instala desde el lock, sin resolver
- run: uv run ruff check .           # 1. lint
- run: uv run ruff format --check .  # 2. formato
- run: uv run mypy src               # 3. tipos
- run: uv run pytest --cov=app ...   # 4. tests
```

Un error de import te falla en diez segundos en vez de al final.

`uv sync --locked` instala **exactamente** lo que dice `uv.lock` y falla si el
lock no coincide con `pyproject.toml`. Eso elimina el "en mi máquina funciona".

El job `docker` tiene `needs: quality`: solo construye la imagen si todo lo
anterior pasó. Construir es lo más lento; no tiene sentido hacerlo sobre
código roto. **Ese job es el punto donde después enganchas el deploy real.**

### 4.3 — Por qué mypy no es opcional

Este es el experimento más instructivo del repo. Rompe una firma a propósito,
cambiando en `user_service.py` el tipo de `user_id` de `int` a `str`:

```python
def get(self, user_id: str) -> UserRead:   # ← estaba int
```

Y ahora corre las dos cosas:

```bash
uv run mypy src     # 2 errores
uv run pytest -q    # 12 passed  (!)
```

**Los 12 tests pasan con el código roto.** Python no verifica tipos al
ejecutar, y los tests casualmente siguen funcionando. Mypy, en cambio,
detecta el problema **y además rastrea el efecto colateral hasta el router**,
un archivo que no tocaste:

```
user_service.py:23: error: Argument 1 to "get" of "UserRepository"
                   has incompatible type "str"; expected "int"
routers/users.py:28: error: Argument 1 to "get" of "UserService"
                   has incompatible type "int"; expected "str"
```

Ahí está la respuesta a "¿para qué tres herramientas?": **atrapan errores
diferentes.** Ruff ve el estilo, mypy ve las inconsistencias de contratos
entre capas, pytest ve el comportamiento. Ninguno reemplaza a otro.

No olvides revertir el cambio: `git checkout src/app/services/user_service.py`

### 4.4 — El Dockerfile y la caché de capas

Archivo: [`Dockerfile`](./Dockerfile)

```dockerfile
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY src ./src
RUN uv sync --locked --no-dev
```

Parece redundante, pero es **caché de capas**. Docker guarda cada instrucción
como una capa y la reutiliza mientras sus archivos de entrada no cambien.

Al copiar primero solo el lock e instalar las dependencias, esa capa pesada se
reutiliza en todos los builds donde no cambiaste dependencias. Copiar el
código *después* significa que editar `main.py` solo invalida las dos últimas
capas. Si copiaras todo de una, cada cambio de una línea reinstalaría todo.

El `--no-dev` deja fuera pytest, mypy y ruff: imagen más chica y menos
superficie de ataque.

### 4.5 — Dependabot

Archivo: [`.github/dependabot.yml`](./.github/dependabot.yml)

Abre PRs semanales con las actualizaciones. Como esos PRs también pasan por
el CI, sabes al instante si la nueva versión rompe algo. Incluye
`github-actions` como ecosistema porque las Actions desactualizadas son un
agujero de seguridad clásico.

---

## Paso 5 — El ciclo del día a día

Esto es lo que se repite por cada cosa que construyas. El historial de este
repo tiene exactamente un ciclo completo para que lo leas:

```bash
git log --oneline --graph --all
```

El ciclo:

```bash
git checkout -b feat/lo-que-sea     # rama nueva (NO genera ningún commit)
# ... programas: schema → repository → service → router → tests ...
uv run pytest                        # verificas en local
git add . && git commit -m "feat: ..."   # pre-commit corre solo
git push -u origin feat/lo-que-sea
gh pr create --fill                  # abre el PR → arranca el CI
# ... si falla: arreglas, commit, push → el CI se repite solo ...
# ... mergeas cuando esté en verde ...
git checkout main && git pull && git branch -d feat/lo-que-sea
```

El `-u origin <rama>` la primera vez vincula tu rama local con la remota;
después basta `git push` a secas.

Ese bucle — rama, código, tests locales, push, PR, CI, merge — es literalmente
el trabajo de un backend en cualquier empresa.

---

## Paso 6 — Lo que falta (y es el ejercicio siguiente)

**1. Proteger `main`.** En Settings → Rules, exige PR y que el check `quality`
pase antes de mergear. Desde ahí, trabaja siempre con ramas y PRs aunque estés
solo. Ojo: en repos privados con cuenta gratis GitHub no aplica estas reglas
— por eso este repo es público.

**2. Cambiar memoria por Postgres.** Acá se cobra la inversión del `Protocol`:
creas `SqlAlchemyUserRepository` con los mismos tres métodos, cambias
`deps.py`, y **`UserService` y los tests unitarios no se tocan ni una línea**.
En el CI agregas un `services:` con Postgres para los tests de integración.

**3. El CD de verdad.** El pipeline llega hasta construir la imagen. El deploy
depende de dónde publiques (Railway, Fly.io, Render, un VPS). Cuando lo
decidas, se agrega un job `deploy` con `needs: docker` que corra solo en `main`.
