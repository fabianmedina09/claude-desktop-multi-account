# Claude Desktop con varias cuentas en macOS

Guía y script para tener **dos o más cuentas de Claude Desktop abiertas al mismo tiempo en un Mac**, cada una con:

- su **nombre** propio (el que se ve en el Dock y en el menú),
- su **icono** propio, de otro color,
- su **sesión** independiente (otro correo, otro historial).

> **Aviso:** proyecto de la comunidad, **no oficial** y sin relación con Anthropic. «Claude» es una marca de Anthropic. El script no modifica tu `Claude.app` original: trabaja sobre una **copia** y la firma localmente. Úsalo bajo tu propia responsabilidad y revisa los términos de uso de Claude.

---

## Índice

1. [Inicio rápido](#inicio-rápido)
2. [Qué es cada parámetro](#qué-es-cada-parámetro)
3. [Iniciar sesión en la segunda cuenta (leer esto)](#iniciar-sesión-en-la-segunda-cuenta-leer-esto)
4. [Paso a paso de lo que hace el script](#paso-a-paso-de-lo-que-hace-el-script)
5. [Por qué no basta un solo comando](#por-qué-no-basta-un-solo-comando)
6. [Actualizar, quitar, varias cuentas](#actualizar-quitar-varias-cuentas)
7. [Solución de problemas](#solución-de-problemas)

---

## Inicio rápido

**Requisitos**

- macOS con [Claude Desktop](https://claude.ai/download) instalado en `/Applications/Claude.app`.
- Xcode Command Line Tools (para `swiftc` y `clang`): `xcode-select --install`.
- Unos 700 MB libres por cuenta (la copia de la app pesa ~656 MB).

**Crear la cuenta**

```bash
git clone https://github.com/fabianmedina09/claude-desktop-multi-cuenta.git
cd claude-desktop-multi-cuenta
./crear-cuenta.sh "Claude Trabajo" Claude-Trabajo amarillo
```

Tarda un par de minutos. Al terminar aparece `~/Applications/Claude Trabajo.app`. Ábrela con doble clic, o desde el Dock. Luego [inicia sesión](#iniciar-sesión-en-la-segunda-cuenta-leer-esto) con el otro correo.

## Qué es cada parámetro

```
./crear-cuenta.sh  "NOMBRE"  PERFIL  COLOR
```

| Parámetro | Para qué sirve | Ejemplo | Si no lo pones |
|---|---|---|---|
| `NOMBRE` | **Nombre visible** de la app: lo que dice el Dock, el menú superior y el nombre del `.app`. | `"Claude Trabajo"` | Obligatorio |
| `PERFIL` | **Carpeta donde se guarda la sesión** (cookies, login, historial). Vive en `~/Library/Application Support/<PERFIL>`. Dos cuentas = dos perfiles distintos. | `Claude-Trabajo` | El nombre con guiones en lugar de espacios |
| `COLOR` | **Color del icono.** Sale del icono original de Claude con el tono cambiado. | `amarillo` | `amarillo` |

Ojo: **no confundas el nombre con el perfil.** El nombre es solo lo que ves. El perfil es lo que separa las sesiones: si dos apps usan el mismo perfil, comparten la cuenta.

**Colores disponibles:** `amarillo`, `verde`, `azul`, `morado`, `rosa`, o uno propio como `ANGULO:EXPOSICION` en radianes (por ejemplo `1.8:0.3`). Solo **amarillo y verde** están verificados visualmente; azul, morado y rosa son cálculos de tono sin comprobar. Si alguno no te gusta, usa el formato propio.

Cambiar el color es cambiar el **icono**: el ángulo es el tono (0 = sin cambio respecto al naranja original, 3.14 ≈ el opuesto) y la exposición lo aclara u oscurece. El amarillo necesita más exposición (0.75) porque un amarillo con el mismo brillo del naranja se ve mostaza oscuro.

## Iniciar sesión en la segunda cuenta (leer esto)

> **La segunda cuenta no deja iniciar sesión con Google.**
>
> Al pulsar «Continuar con Google» el navegador intenta **abrir Claude** (con un enlace `claude://…`) y macOS lo entrega a **la sesión principal**, la que ya estaba abierta, no a la segunda. Entonces ves la cuenta original en vez de la nueva.

**Lo que funciona: iniciar sesión con correo y código**

1. En la ventana de la segunda app, elige **continuar con correo electrónico** y escribe el correo de la segunda cuenta.
2. Claude te envía un **código** a ese correo.
3. Abre el correo, **copia el código** y pégalo en la app. (Si el correo trae un enlace, no lo uses: usa el código.)
4. **En ningún momento le digas al navegador que abra Claude.** Si aparece el aviso «¿Abrir Claude?», cancélalo o ciérralo. Ese aviso es justo lo que manda el inicio a la sesión principal.
5. Pega el código en la app. Con eso la autenticación queda completa.

Esto se hace una sola vez. La sesión queda guardada en el perfil y las siguientes veces la app abre ya con esa cuenta.

## Paso a paso de lo que hace el script

El script `crear-cuenta.sh` hace cinco cosas. Si quieres entenderlo o hacerlo a mano, aquí está cada una y por qué existe.

**1. Icono de otro color.** Extrae el icono original (`electron.icns`) y le cambia el tono y la exposición con CoreImage. Genera un `.icns` nuevo.

**2. Lanzador.** Crea `~/Applications/<NOMBRE>.app`, un lanzador pequeño (AppleScript compilado con `osacompile`) con el mismo icono. Es lo que se abre con doble clic.

**3. Copia de Claude con identidad propia.** Copia `/Applications/Claude.app` dentro del lanzador (`Contents/Resources/<NOMBRE>.app`) y le cambia:

- el icono (`electron.icns`),
- `CFBundleIdentifier` → `com.anthropic.claudefordesktop.<nombre>` (para que macOS la trate como otra app),
- `CFBundleDisplayName` → el nombre visible,
- y **borra `CFBundleIconName`** del `Info.plist` (si no, el Dock sigue mostrando el icono original, porque lo toma del catálogo `Assets.car`).

**4. Perfil fijo.** Cambia el ejecutable principal por un lanzador diminuto compilado en C que ejecuta el binario real (`Claude-bin`) **siempre** con `--user-data-dir=~/Library/Application Support/<PERFIL>`. Así, aunque abras la copia desde el icono del Dock, entra a su perfil y no al principal.

**5. Firma y refresco.** Firma la copia de forma local (`codesign --sign -`), y reinicia el Dock para que muestre el icono nuevo.

Estructura final:

```
~/Applications/<NOMBRE>.app              ← lanzador (lo que abres)
└── Contents/Resources/<NOMBRE>.app      ← copia de Claude con identidad propia
    └── Contents/MacOS/Claude            ← lanzador en C que fija el perfil
        Contents/MacOS/Claude-bin        ← el binario real de Claude
```

## Por qué no basta un solo comando

Lo más simple sería un lanzador que ejecute:

```bash
open -n -a "Claude" --args --user-data-dir="$HOME/Library/Application Support/Claude-Trabajo"
```

Eso **sí abre una segunda instancia con otra sesión**, y sirve si solo quieres eso. Pero tiene límites:

- **Se ve igual que la principal.** El Dock muestra el programa que corre (`Claude.app`), no el lanzador. Nombre «Claude» e icono naranja en las dos.
- **Si la abres desde el Dock** (porque la dejaste fijada), macOS lanza la app sin el parámetro del perfil y entra a la sesión principal.
- **Si abres la principal mientras la otra está abierta**, macOS a veces trae al frente la que ya existe, porque ambas son «la misma app».

Por eso el script usa una copia con identificador propio y fija el perfil dentro de la copia.

Detalles que costó descubrir (por si lo haces a mano):

- Electron busca sus procesos auxiliares (`Claude Helper.app`, etc.) usando **`CFBundleName`**. Si lo cambias, falla con `Unable to find helper app`. Déjalo en `Claude` y cambia solo `CFBundleDisplayName`.
- El ejecutable principal tiene que ser un binario real (Mach-O), no un script de shell.
- Hay que **quitar `CFBundleIconName`** para que el Dock respete tu `.icns`.
- Tras tocar el bundle hay que volver a firmarlo. Un archivo suelto dentro del `.app` rompe la firma (`unsealed contents present in the bundle root`).

## Actualizar, quitar, varias cuentas

**Cuando Claude Desktop se actualice**, la copia **no** se actualiza sola. Vuelve a correr el mismo comando: reconstruye la app y **conserva la sesión** (vive en el perfil, fuera de la app).

**Quitar una cuenta:** arrastra `~/Applications/<NOMBRE>.app` a la papelera. Para borrar también la sesión:

```bash
rm -rf "$HOME/Library/Application Support/<PERFIL>"
```

**Más de dos cuentas:** corre el script otra vez con otro `NOMBRE`, otro `PERFIL` y otro `COLOR`. Cada una es independiente.

**Dónde guarda la app el script:** por defecto en `~/Applications`. Cámbialo con `DESTINO=/otra/ruta ./crear-cuenta.sh …`.

## Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Al iniciar sesión se abre la cuenta principal | Usaste Google / dejaste que el navegador abriera Claude | [Entrar con correo y código](#iniciar-sesión-en-la-segunda-cuenta-leer-esto) |
| El Dock muestra el icono o nombre viejo | Caché de macOS | Salir de la app, `killall Dock`, abrirla de nuevo |
| `Unable to find helper app` | `CFBundleName` cambiado | Dejarlo en `Claude` |
| No arranca, «incorrect executable format» | Firma rota o ejecutable no binario | Volver a correr el script |
| Falta `swiftc` o `clang` | Sin Xcode Command Line Tools | `xcode-select --install` |
| La app dejó de funcionar tras actualizar Claude | La copia quedó desactualizada | Volver a correr el script |

## Licencia

MIT. Ver [LICENSE](LICENSE).
