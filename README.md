# Pokémon Z (V2.15) — QoL & Debug Mod 🚀

> ⚠️ **MOD no oficial**. Este repositorio solo contiene los archivos que modifican el juego. El juego original es propiedad de **Lostie Fangames**.

Este mod inyecta mejoras de calidad de vida (QoL) y herramientas de depuración avanzadas en **Pokémon Z (Versión 2.15)** "al vuelo", sin tocar los archivos originales del juego.

> **Nota Personal**: Tengo muchas ganas de jugar Pokémon Z por completo (lo tengo pendiente). Anteriormente ya disfruté muchísimo de **Pokémon Iberia**, otro gran trabajo del creador, y este proyecto es mi forma de agradecer y mejorar la experiencia para otros jugadores.

---

## 📸 Galería Visual (Mejoras en acción)

![HUD de Combate Inteligente (STAB y Efectividad)](./screenshots/Captura%20de%20pantalla%202026-03-19%20214930.png)
*HUD de Combate: Indicadores de efectividad (+) (-) y STAB en tiempo real.*

![Selector de Formas Visual](./screenshots/Captura%20de%20pantalla%202026-03-19%20215010.png)
*Herramientas Debug: Selector de Formas (Megas, Alola, Galar) totalmente visual por nombres.*

![Buscador Dinámico](./screenshots/Captura%20de%20pantalla%202026-03-19%20214944.png)
*Buscador Inteligente: Filtra por texto para asignar Especies, Habilidades o Movimientos.*

![Control de Tipos Custom](./screenshots/Captura%20de%20pantalla%202026-03-19%20220109.png)
*Customización: Forzar tipos personalizados en cualquier Pokémon de tu equipo.*

![Resumen de Estadísticas y Naturalezas](./screenshots/Captura%20de%20pantalla%202026-03-19%20215028.png)
*Stats Scene: Visualización de Naturalezas e IVs/EVs mejorada en el menú Debug.*

![Editor de Movimientos y Especiales](./screenshots/Captura%20de%20pantalla%202026-03-19%20215405.png)
*Moveset Editor: Gestión rápida de ataques y movimientos especiales.*

![Navegación Intuitiva](./screenshots/Captura%20de%20pantalla%202026-03-19%20215328.png)
*Navegación: Menús más rápidos y descriptivos para una depuración ágil.*

## 🗡️ Heizo — NPC Exclusivo (Boss del Mod)

El mod incluye un **NPC exclusivo llamado Heizo** (el creador del mod) que puedes encontrar en el Centro Pokémon. Es un encuentro cinematográfico al estilo de un Líder de Gimnasio:

- 🎵 **Música propia**: Suena `Acertijos` al hablar con él y `CombateLider` al combatir.
- 🗣️ **Diálogos dramáticos**: Frases únicas al sacar cada Pokémon y al ser derrotado.
- ⚔️ **Equipo de Boss**: Charizard Shiny Mega Y, Venusaur y Gengar con sets competitivos a tu nivel.
- 🛒 **Mercado Negro**: Si le derrotas, desbloqueas una tienda con objetos especiales a mitad de precio.

> El sprite, la música y todos los datos de Heizo están incluidos en el ZIP. No necesitas nada extra.

---

## 📦 Elige tu versión (4 vs 8 Movimientos)

Este repositorio ofrece dos experiencias distintas para adaptarse a tu estilo de juego. Puedes encontrar los archivos listos para usar en la carpeta [`Versiones/`](./Versiones):

1.  **Versión Expandida (8 Movimientos)**:
    *   **Ubicación**: Carpeta raíz (es la versión por defecto) o en [`Versiones/Expanded_8_Movimientos`](./Versiones/Expanded_8_Movimientos).
    *   **Qué incluye**: Soporte para hasta 8 ataques por Pokémon, UI de resumen paginada, y todas las mejoras de QoL y Debug.
2.  **Versión Clásica (4 Movimientos)**:
    *   **Ubicación**: [`Versiones/Classic_4_Movimientos`](./Versiones/Classic_4_Movimientos).
    *   **Qué incluye**: Mantiene el límite original de 4 movimientos de Essentials, pero conserva todas las demás mejoras de Debug y QoL (HUD, buscador, etc.).

### Cómo cambiar de versión:
1. Entra en la carpeta de la versión que prefieras dentro de `Versiones/`.
2. Copia el archivo `preload.rb` de esa carpeta.
3. Pégalo en la raíz de tu juego (donde está el ejecutable .exe), reemplazando el archivo anterior.

---

## 💾 ¡NUEVO!: Modo Portable (Sincronización Universal) 

He implementado un **sistema de autoguardado inteligente** que detecta si estás jugando desde un dispositivo externo (pendrive o disco duro portable):

- **Sincronización Automática**: El juego detecta si hay una partida más reciente en la carpeta `Partidas Guardadas` del disco duro y la "inyecta" al PC al iniciar.
- **Respaldo en Vivo**: Mientras juegas, el mod vigila el archivo de guardado nativo de Windows. En cuanto guardas la partida, se hace una copia instantánea al disco duro portable.
- **Sin Configuración**: No tienes que hacer nada. Solo asegúrate de que la carpeta `Partidas Guardadas` esté junto al ejecutable del juego.

---

## ⚡ Instalación en 1 minuto (Copiar y Pegar)

1. **Descarga el ZIP** de este repositorio → botón verde `Code > Download ZIP`.
2. **Extrae el ZIP** y copia **TODO el contenido** dentro de la carpeta de tu juego Pokémon Z V2.15.
3. **Reemplaza** los archivos cuando Windows te lo pida (solo sobreescribe, no borra nada del juego original).
4. **¡Y listo!** Abre el juego normalmente.

> [!NOTE]
> El ZIP ya incluye todos los archivos necesarios: `preload.rb`, `mkxp.json`, los datos (`Data/`), el sprite de Heizo y su música. No necesitas nada más.


---

## 🧠 Lo que he aprendido en este proyecto

Mantenre este repositorio me ha permitido profundizar en aspectos técnicos avanzados de desarrollo y hacking de juegos basados en RGSS (Ruby Game Scripting System):

### 1. Inyección Dinámica y Metaprogramación
No hemos tocado ni una línea del código original encriptado. En su lugar, hemos usado **metaprogramación en Ruby**:
- **`class_eval`**: Para abrir las clases `core` del motor (como `PokeBattle_Pokemon`) en tiempo de ejecución.
- **`alias_method`**: Para crear "ganchos" (hooks) que nos permiten ejecutar nuestro código antes o después del original sin romper la lógica interna del juego.

### 2. Acceso a Nivel de Sistema (Win32API)
Para que los atajos de teclado (`ç`, `+`, `-`) fueran instantáneos y no dependieran de la cola de eventos del juego, hemos implementado llamadas directas a la API de Windows:
- Usando `GetAsyncKeyState` de `user32.dll`, logramos detectar pulsaciones en tiempo real, saltándonos las limitaciones de entrada del motor Essentials original.

### 3. Optimización de UI y Experiencia de Usuario (UX)
Hemos rediseñado pantallas de Debug que originalmente eran solo números y las hemos convertido en menús intuitivos:
- Procesamiento de arrays dinámicos para mostrar nombres en lugar de IDs.
- Implementación de algoritmos de búsqueda/filtrado en tiempo real dentro de las cajas de mensaje del juego.

### 4. Gestión de Proyectos con Git
Aprendizaje de flujos de trabajo profesionales:
- **Clean History (Squashing)**: Mantener un historial de cambios limpio y presentable.
- **Orphan Branches**: Para purgar archivos pesados del juego base y subir solo "lo justo" (el código del mod).

---

## ✨ Qué incluye este Mod
- **HUD de Combate Accesible**: Pensado para daltonismo y rapidez estratégica.
- **Suite Debug Pro**: Filtros inteligentes (`*`) para ver solo movimientos/habilidades compatibles.
- **Atajos de Teclado Rápidos**:
    - `ç` : Activa/Desactiva Modo Debug instantáneamente.
    - `+` : Curación instantánea del equipo.
    - `-` : Suma 99 Caramelos Raros automáticos.

---

## 🙏 Créditos y Agradecimientos Especiales

Todo el reconocimiento al increíble trabajo de:

**Lostie Fangames** — Desarrollador de Pokémon Z y Pokémon Iberia. Gracias por los años de dedicación a la comunidad.
- 🌐 [Blog Oficial de Lostie Fangames](https://lostiefangames.blogspot.com/)
- 📥 [Página Directa de Pokémon Z](https://lostiefangames.blogspot.com/p/pokemon-z.html)

**Dan Espinosa** — Autor de la magnífica banda sonora.
- 🎵 [Banda Sonora en Bandcamp](https://danespinosa.bandcamp.com/album/pok-mon-z-bso)

---
*Este proyecto es de código abierto para que la comunidad pueda aprender sobre inyección en Ruby.*
