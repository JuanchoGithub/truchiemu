---
layout: default
title: "Depurando lo Invisible: Por qué los Juegos de Dreamcast No Podían Guardar"
description: Un análisis técnico profundo sobre cómo corregir los guardados VMU de Dreamcast en Flycast - ciclos de vida de opciones de core, semántica de la API libretro y análisis binario.
last_updated: May 2026
---

# Depurando lo Invisible: Por qué los Juegos de Dreamcast No Podían Guardar en Nuestro Emulador

Pasamos la mayor parte de una semana rastreando un bug donde los juegos de Dreamcast en TruchiEmu simplemente no podían guardar. Sin mensaje de error, sin cuelgue — solo silencio. La VMU (Visual Memory Unit, la tarjeta de memoria del Dreamcast) simplemente no existía en lo que a los juegos respecta. Lo que siguió fue un viaje a través de análisis binario de código fuente cerrado, semántica de la API libretro y una cadena incorrecta que se cascó en un fallo total. Así es como lo encontramos y lo corregimos.

---

## El Problema de Memoria del Dreamcast

El Dreamcast es inusual entre las consolas en que sus tarjetas de memoria — las VMUs — se conectan al controlador, no a la consola. Cada controlador tiene dos ranuras de expansión, y la VMU va en la ranura 1. Desde la perspectiva del emulador, esto significa que la VMU no es un simple archivo en disco — es un **dispositivo de bus maple** que tiene que ser explícitamente creado y adjunto a un puerto de controlador en tiempo de ejecución.

Flycast, el core de libretro que usamos para la emulación de Dreamcast, gestiona esto a través de su sistema de opciones. Opciones de core como `reicast_device_port1_slot1` controlan qué está conectado en cada ranura. Los valores posibles son: `VMU`, `Purupuru` (un paquete de vibración), `DreamPotato` (un periférico de terceros) y `None`. Si la ranura 1 de un controlador no está configurada como `VMU`, los juegos no tienen dónde guardar. Ese era nuestro problema.

---

## La Configuración: Cómo Pensábamos que Funcionaba

Teníamos un archivo `CoreOverrides.json` que establecía valores predeterminados para las opciones del core — cosas como modo de renderizado, threading y asignaciones de puertos de dispositivo. Para el Dreamcast, configuramos la ranura 1 de cada controlador como `"Visual Memory"`, porque eso es lo que dice la etiqueta de la interfaz de la opción:

```json
"reicast_device_port1_slot1": "Visual Memory"
```

Parece razonable, ¿verdad? "Visual Memory" es lo que Flycast muestra en su menú de opciones. Ese es el nombre por el que todos conocen la VMU. También era completamente incorrecto.

---

## Trampa #1: Etiquetas vs. Valores

La API de opciones de core de libretro tiene un concepto de **valores** y **etiquetas**. Los valores son lo que el código compara. Las etiquetas son lo que los humanos ven en un menú. A menudo son diferentes, especialmente para opciones con caracteres especiales, preocupaciones de localización o nombres heredados.

Descubrimos esto por las malas haciendo un volcado hex del binario de Flycast:

```
0x57d4c6: VMU
0x57d4ca: Purupuru
0x57d4d3: DreamPotato
0x57d4df: None
```

Estas son las cadenas de **valor** — lo que `update_variables()` de Flycast realmente pasa a `strcmp()`:

```cpp
if (!strcmp("VMU", var.value))
config::MapleExpansionDevices[port][slot] = MDT_SegaVMU;
else if (!strcmp("Purupuru", var.value))
config::MapleExpansionDevices[port][slot] = MDT_PurupuruPack;
```

`"Visual Memory"` nunca coincide. No con `VMU`, no con `Purupuru`, no con nada. Pasa por todas las ramas. Pero empeora. Como `var.value` no es NULL — es `"Visual Memory"`, una cadena real — el valor predeterminado fallback que habría establecido una VMU también se salta. El código asume que si el valor no coincidió con ninguna opción conocída, fue intencionalmente configurado a algo inusual. El resultado: la configuración del dispositivo de expansión nunca se actualiza, y Flycast recurre a su predeterminado interno, que es **Purupuru** (un paquete de vibración). Sin VMU. Sin guardados. La corrección fue una línea en CoreOverrides.json, pero encontrarla requirió análisis binario porque el código fuente de libretro de Flycast había divergido del binario compilado que estábamos ejecutando.

> **Lección:** En la API de libretro, los valores de opciones y las etiquetas son cosas separadas. Siempre usa el valor, no la etiqueta, al establecer opciones programáticamente. Si estás trabajando con un binario que no compilaste, verifica las cadenas reales.

---

## Trampa #2: La Guardia de Primer Inicio

Incluso después de corregir el valor a `"VMU"`, había un problema de timing. La función `update_variables()` de Flycast tiene un parámetro `first_startup`:

```cpp
static void update_variables(bool first_startup)
{
config::Settings::instance().load(false);
// ... procesa muchas opciones ...

if (!first_startup) {
// Las opciones de puertos de dispositivo SOLO se procesan aquí
for (int port = 0; port < 4; port++) {
// lee opciones reicast_device_port*_slot*
// establece MapleExpansionDevices en consecuencia
}
devices_need_refresh = true;
}
}
```

Durante `retro_load_game()`, Flycast llama `update_variables(true)`. Las opciones de puertos de dispositivo se **saltan completamente** en la primera llamada. La lógica tiene sentido: durante el inicio inicial, el core no ha inicializado completamente su emulación de hardware, así que configurar dispositivos maple prematuramente podría causar problemas. En su lugar, Flycast crea dispositivos con sus predeterminados internos (Purupuru en la ranura 1) y difiere las asignaciones de puertos de dispositivo configuradas por el usuario a una llamada posterior.

Esto significa que nuestra anulación `"VMU"` estaba sentada en `g_optValues`, lista para ser devuelta, pero Flycast nunca la pidió durante la única lectura de opciones que ocurrió antes de que se crearan los dispositivos.

> **Lección:** Los cores de libretro no necesariamente leen todas sus opciones al mismo tiempo. Algunas opciones están bloqueadas detrás del estado de inicio. Necesitas entender el ciclo de vida específico de lectura de opciones del core, no solo el contrato de la API.

---

## Trampa #3: La Señal de Actualización de Variables

La API de libretro proporciona `RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE` — un callback que el core consulta para verificar si los valores de las opciones han cambiado desde la última lectura. Si devuelve `true`, el core debería releer sus opciones. Flycast verifica esto al inicio de cada `retro_run()`:

```cpp
void retro_run()
{
bool updated = false;
if (environ_cb(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &updated) && updated)
update_variables(false); // first_startup=false — puertos de dispositivo AHORA procesados

if (devices_need_refresh)
refresh_devices(false); // llama maple_ReconnectDevices()

if (first_run)
emu.start(); // inicia emulación con dispositivos correctos

// ... renderizar fotograma ...
first_run = false;
}
```

Esta es la secuencia clave: `update_variables(false)` → `refresh_devices(false)` → `emu.start()`. Si pudiéramos señalar `GET_VARIABLE_UPDATE = true` después de `retro_load_game()` pero antes del primer `retro_run()`, Flycast releería opciones con `first_startup=false`, procesaría las asignaciones de puertos de dispositivo, crearía VMUs y luego comenzaría la emulación con la configuración de dispositivo correcta.

Pero el callback de TruchiEmu siempre devolvía `false`. No teníamos mecanismo para decirle a Flycast "oye, tus opciones cambiaron." Nuestra corrección: un flag global establecido después de `retro_load_game()`:

```objc
// LibretroBridgeImpl.mm — después de retro_load_game() para cores Flycast
if (g_coreID && [[g_coreID lowercaseString] containsString:@"flycast"]) {
g_variablesUpdated = YES;
[self setControllerPortDevice:1 device:device_type];
[self setControllerPortDevice:2 device:device_type];
[self setControllerPortDevice:3 device:device_type];
}
```

```objc
// LibretroCallbacks.mm — manejador GET_VARIABLE_UPDATE
case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
{
bool updated = g_variablesUpdated;
if (updated) {
g_variablesUpdated = NO; // consume el flag — devuelve true una vez
}
if (data)
*(bool *)data = updated;
return true;
}
```

El flag se **consume al leerlo**. Devuelve `true` exactamente una vez, luego se reinicia. Esto dispara `update_variables(false)` de Flycast en el primer fotograma, lo cual procesa las opciones de puertos de dispositivo, lo cual detecta nuestro valor `"VMU"`, lo cual establece `MDT_SegaVMU`, lo cual dispara `refresh_devices(false)`, lo cual llama `maple_ReconnectDevices()`, lo cual recrea todos los dispositivos maple con VMUs en la ranura 1. Luego `emu.start()` se ejecuta, y el Dreamcast arranca con tarjetas de memoria.

> **Lección:** La API de libretro es una conversación, no un archivo de configuración. Algunos cores necesitan que se les *diga* que releean opciones; no lo harán por su cuenta. Entender qué señales de la API disparan qué transiciones de estado interno es crítico.

---

## Trampa #4: Valores de Opciones Leídos Sin GET_VARIABLE

Como si los problemas de timing no fueran suficientes, algunos cores de libretro leen valores de opciones a través de rutas de código internas que no pasan por `RETRO_ENVIRONMENT_GET_VARIABLE` en absoluto. Acceden a su sistema de configuración directamente. Para manejar esto, agregamos **precarga** — inyectando anulaciones JSON directamente en el diccionario `g_optValues` en el momento de inicialización del core, antes de que Flycast consulte cualquier cosa:

```objc
void core_override_apply_all_to_optvalues(const char* coreID) {
if (!coreID || !g_optValues) return;
NSString* coreStr = [NSString stringWithUTF8String:coreID];
NSDictionary* allOverrides = [CoreOverrideBridge getAllOverridesFor:coreStr];
if (!allOverrides || allOverrides.count == 0) return;

for (NSString* key in allOverrides) {
NSString* value = allOverrides[key];
if (key.length > 0 && value.length > 0) {
g_optValues[key] = value;
}
}
}
```

Esto se llama desde `applyPersistedOverrides()`, que se ejecuta durante `SET_CORE_OPTIONS`. La estratificación de anulaciones es:

1. **Anulaciones JSON** (nuestros predeterminados) — aplicadas primero
2. **Anulaciones .cfg** (opciones guardadas del usuario) — aplicadas encima, siempre ganando

Esto asegura que nuestros predeterminados de VMU estén en su lugar para cualquier ruta de código que Flycast use para leer opciones, mientras sigue respetando cualquier configuración explícita del usuario.

> **Lección:** Al conectar dos sistemas (una app Swift y un core de emulador C++), no puedes asumir que toda la comunicación pasa por la API oficial. Las rutas de código internas pueden eludir tus callbacks. La precarga defensiva asegura consistencia independientemente de qué ruta tome el core.

---

## Trampa #5: Archivos VMU Faltantes y Corruptos

Incluso con todas las correcciones de software anteriores, las VMUs no funcionarán si los archivos de guardado reales no existen en disco. Flycast busca archivos VMU en el directorio del sistema (`system/dc/`), específicamente archivos como `vmu_save_A1.bin` hasta `vmu_save_D1.bin`. Cada uno debe ser exactamente de 128KB — un sistema de archivos FAT12 formateado apropiadamente con 200 bloques libres.

Empaquetamos archivos VMU pre-formateados en `dreamcast.zip` junto con los archivos BIOS, y extendimos `DreamcastBIOSService` para extraerlos y validarlos:

```swift
private func repairCorruptVMUFiles() {
for file in vmuFiles {
let url = dcDirectory.appendingPathComponent(file)
guard fm.fileExists(atPath: url.path) else { continue }

// ¿Tamaño incorrecto? Eliminar y re-extraer
if size != vmuExpectedSize {
try? fm.removeItem(at: url)
continue
}

// ¿Todo ceros? (Flycast puede poner a cero las VMUs en un cierre incorrecto)
if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
data.allSatisfy({ $0 == 0 }) {
try? fm.removeItem(at: url)
}
}
}
```

La verificación de corrupción importa. Descubrimos que cuando Flycast se apaga sin desmontar apropiadamente el sistema de archivos VMU (por ejemplo, si el usuario fuerza el cierre), puede escribir un archivo lleno de ceros. Un archivo de 128KB lleno de ceros pasa la verificación de tamaño pero es un sistema de archivos corrupto. Los juegos lo ven como una tarjeta sin formatear y no pueden guardar. Nuestra lógica de reparación detecta esto y re-extrae la VMU conocida como buena del bundle.

> **Lección:** Los cores de emuladores pueden corromper sus propios archivos de guardado. Validar la integridad de los archivos (no solo la existencia) es esencial para una experiencia confiable.

---

## El Bug de la Guardia Invertida

Mientras depurábamos la extracción de VMU, encontramos un error lógico en `ensureExtracted()` que había estado previniendo silenciosamente que los archivos VMU se desplegaran:

```swift
// ANTES — lógica invertida: retorna temprano cuando los archivos FALTAN
guard hasAllFiles && hasAllVMUFiles else { return }

// DESPUÉS — correcto: retorna temprano solo cuando todos los archivos ESTÁN PRESENTES
if hasAllFiles && hasAllVMUFiles { return }
```

El patrón `guard ... else { return }` retorna cuando la condición es **falsa** — es decir, cuando faltan archivos. La función se estaba cancelando exactamente cuando debería haber estado extrayendo archivos. Este fue un clásico escollo de Swift: `guard` está diseñado para retorno temprano en **fallo**, pero la lógica estaba escrita como si fuera una declaración `if` para **éxito**.

> **Lección:** La declaración `guard` de Swift invierte el flujo de control comparada con `if`. Siempre verifica la dirección del retorno temprano al convertir entre ambas.

---

## La Cadena Completa

Esto es lo que pasa ahora cuando un juego de Dreamcast se inicia en TruchiEmu:

1. **Inicio de la app** — `DreamcastBIOSService.ensureExtracted()` valida y extrae archivos VMU a `system/dc/`
2. **Carga del core** — `SET_CORE_OPTIONS` → `parseCoreOptionsV2()` almacena predeterminados de opciones en `g_optValues`
3. **Precarga de anulaciones** — `core_override_apply_all_to_optvalues()` escribe `"VMU"` en `g_optValues` para todas las entradas device port slot1
4. **`retro_load_game()`** — Flycast llama `update_variables(true)` → opciones de puertos de dispositivo **saltadas** (first_startup) → dispositivos creados con predeterminados Purupuru
5. **Post-carga** — TruchiEmu establece `g_variablesUpdated = YES` + llama `setControllerPortDevice` para puertos 1-3
6. **Primer `retro_run()`** — Flycast consulta `GET_VARIABLE_UPDATE` → devuelve `true` → `update_variables(false)` → opciones de puertos de dispositivo **procesadas** → `strcmp("VMU", "VMU")` coincide → `MapleExpansionDevices` establecido a `MDT_SegaVMU` → `devices_need_refresh = true`
7. **Mismo fotograma** — `refresh_devices(false)` → `maple_ReconnectDevices()` → controladores recreados con VMUs en ranura 1
8. **Mismo fotograma** — `emu.start()` → la emulación comienza con VMUs equipadas
9. **El juego guarda** → escribe en `system/dc/vmu_save_A1.bin`

Desde la perspectiva del usuario, simplemente funciona. El juego ve tarjetas de memoria, los guardados ocurren, y los archivos están ahí la próxima vez que arranca.

---

## Lo Que Aprendimos

**El análisis binario a veces es inevitable.** No podíamos averiguar por qué `"Visual Memory"` no funcionaba solo desde el código fuente — el binario que estábamos ejecutando había divergido del último código fuente. Los volcados hex y las búsquedas de cadenas fueron la única forma de encontrar las cadenas de valor reales.

**La API de libretro es engañosamente simple.** `GET_VARIABLE` parece un almacén de clave-valor, pero la realidad es que los cores tienen ciclos de vida complejos de lectura de opciones con guardias de inicio, señales de refresco y rutas de código internas que eluden la API completamente. Tienes que entender el comportamiento específico de cada core.

**La integración de emuladores es integración profunda.** No solo estás pasando configuración a una librería — estás conectando dos entornos de ejecución con diferentes ciclos de vida, diferente gestión de estado y diferentes suposiciones sobre quién posee qué. Los bugs viven en los huecos entre esos entornos.

**Los bugs más difíciles son los silenciosos.** Sin cuelgue, sin mensaje de error, sin línea de log. Solo una tarjeta de memoria que no existe. La corrección fue una sola cadena en un archivo JSON, pero encontrar esa cadena requirió entender todo el ciclo de vida de lectura de opciones de un core de emulador de código fuente cerrado.

---

## Archivos Modificados

| Archivo | Cambio |
|---------|--------|
| `TruchiEmu/Resources/Config/CoreOverrides.json` | `"Visual Memory"` → `"VMU"` para todas las entradas `*_device_port*_slot1` |
| `TruchiEmu/Core/Engine/LibretroCallbacks.mm` | El manejador `GET_VARIABLE_UPDATE` devuelve el flag `g_variablesUpdated` |
| `TruchiEmu/Core/Engine/LibretroGlobals.h` | Agregada declaración `extern BOOL g_variablesUpdated` |
| `TruchiEmu/Core/Engine/LibretroGlobals.mm` | Agregada definición `BOOL g_variablesUpdated = NO` |
| `TruchiEmu/Core/Engine/LibretroBridgeImpl.mm` | Establece `g_variablesUpdated = YES` + `setControllerPortDevice` para puertos 1-3 después de `retro_load_game()` (solo Flycast) |
| `TruchiEmu/Core/Engine/CoreOverrideBridge.h` | Declarada `core_override_apply_all_to_optvalues()` |
| `TruchiEmu/Core/Engine/CoreOverrideBridge.mm` | Implementada `core_override_apply_all_to_optvalues()` — inyecta anulaciones JSON en `g_optValues` |
| `TruchiEmu/Resources/System/dreamcast.zip` | Agregados 4 archivos VMU pre-formateados de 128KB (`vmu_save_A1.bin` hasta `vmu_save_D1.bin`) |
| `TruchiEmu/Services/DreamcastBIOSService.swift` | Lógica de extracción, validación y reparación de corrupción de VMU |
