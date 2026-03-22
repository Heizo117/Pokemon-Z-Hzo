# Mi Resumen de Mejoras y Optimizaciones (Versión 1889 líneas)

Este documento detalla los cambios técnicos y de diseño que he realizado sobre el juego base (Versión 2.15) para elevar la calidad, la accesibilidad y la facilidad de depuración del proyecto.

## 1. Justificación Técnica: Inyección vía `preload.rb`

A diferencia del método tradicional de modificar los scripts internos del programa con el que se creó el juego (RPG Maker XP / Essentials), he optado por una **inyección dinámica** a través del archivo `preload.rb`.

-   **Ventajas de mi enfoque**:
    *   **No destructivo**: No altero los archivos originales de datos o scripts encriptados.
    *   **Portabilidad**: Los cambios se aplican al vuelo al iniciar el juego, facilitando actualizaciones y evitando conflictos de compilación.
    *   **Flexibilidad**: Me permite sobreescribir métodos de clases `core` (como el HUD de batalla o el equipo Pokémon) de forma limpia y reversible.

## 2. Inclusividad y Accesibilidad (HUD de Combate)

He rediseñado el HUD de batalla pensando en la experiencia del jugador y en la **accesibilidad (especialmente para jugadores con daltonismo)**:

-   **Indicadores de Efectividad**: En lugar de depender únicamente de los colores de los tipos o mensajes de texto, ahora el HUD muestra indicadores visuales directos sobre el objetivo:
    *   `(+)` : Súper Efectivo
    *   `(-)` : Poco Efectivo
    *   `(X)` : Sin Efecto
    *   `STAB`: He añadido también un brillo pulsante en la caja del movimiento si tiene bonificación por mismo tipo y es eficaz.
-   **Facilidad de Lectura**: Esto permite a cualquier jugador identificar rápidamente la mejor estrategia sin memorizar tablas de tipos complejas ni depender de la percepción del color.

## 3. Herramientas de Depuración (Debug) de Próxima Generación

He transformado el modo depurador en una suite de herramientas profesional:

-   **Buscador Inteligente Universal (Filtro por Texto)**: Atrás quedaron los días de desplazarse por listas infinitas. Ahora los menús de asignación de Especies, Habilidades, Movimientos y Naturalezas incluyen un buscador de texto en tiempo real que filtra por nombre y descripción.
-   **Sistema de Filtros Especializados ("*")**: 
    *   En el menú de Movimientos: Al buscar `*` el sistema cruza datos internos y muestra **únicamente los movimientos compatibles** (por nivel, MT/MO y Huevo) para ese Pokémon específico.
    *   En el menú de Habilidades: Al buscar `*` resalta las habilidades naturales que puede tener esa especie frente a la lista completa.
-   **Menú de Formas Dinámico**: Se ha sustituido el antiguo e infame selector numérico de formas de Essentials. El nuevo sistema escanea los sprites disponibles y genera un **menú visual con los nombres reales de las formas** (detectando automáticamente Megas X/Y, formas Regionales de Alola/Galar/Hisui, y diferenciando entre formas con cambios de estadísticas reales vs formas puramente estéticas).
-   **Control Total de Estadísticas (Base/IV/EV)**: He añadido un menú de edición directa de estadísticas (`PBStats`) que permite modificar manualmente el HP, Ataque, Defensa, etc., de cualquier Pokémon. El sistema se encarga de ajustar los IVs y EVs necesarios para que el cambio sea persistente y real.
-   **Asignador de Objetos Avanzado ("Dar Objeto")**: Integración de un buscador de objetos que permite filtrar por nombre, descripción o utilidad (ej. buscar "piedra" o "bayas") para equipar cualquier objeto del juego directamente desde el menú de depuración, sin pasar por la mochila.
-   **Control Total de Tipos Custom**: He añadido la capacidad de reescribir manualmente el `Tipo 1` y `Tipo 2` de cualquier Pokémon de tu equipo desde su pantalla de Datos. Permite saltarse las limitaciones de la especie original para testear mecánicas de STAB y debilidades personalizadas al vuelo.
-   **Buscador Universal de Especies y Movimientos**: Los menús de "Añadir Pokémon" y "Enseñar Movimiento" ahora cuentan con el mismo motor de búsqueda avanzada, permitiendo encontrar cualquier especie o técnica por nombre o número de Pokédex de forma instantánea.
-   **Corrección de Stats Dinámicos**: Integración de recálculo instantáneo de estadísticas (`calcStats`) cada vez que se inyecta un cambio en la forma, tipo, estadísticas o naturaleza mediante las herramientas Debug, evitando tener que meter/sacar al Pokémon del PC para aplicar los cambios.

## 4. Mejoras en UI y Calidad de Vida (QoL)

-   **HUD de Equipo y PC**: He integrado un botón de PC en el equipo que sincroniza el sistema de almacenamiento en tiempo real.
-   **Navegación Fluida**: He programado el cursor para que salte automáticamente huecos vacíos y vuelva al último Pokémon disponible al subir desde los botones inferiores, evitando "puntos muertos" en la interfaz.
-   **Atajos Instantáneos de Testeo (Inyecciones de Teclado)**: He programado macros directos desde el teclado para pruebas rápidas sin pasar por el menú original y gestionar al vuelo herramientas de desarrollo:
    *   **Tecla `ç`** (o `º` según la distribución del teclado): Activa o desactiva por completo el **Modo Debug** (Modo Desarrollador) al vuelo en cualquier momento, emitiendo un sonido de confirmación.
    *   **Tecla `+`** (Teclado numérico o junto a Enter): Cura a todo el equipo al instante sin animaciones ni interrupciones.
    *   **Tecla `-`** (Teclado numérico o guion): Añade 99 Caramelos Raros directamente a tu mochila al instante.
    *   *(En reserva)* **Tecla `F3`**: Se ha dejado preparado en el código (actualmente comentado/inactivo) un atajo para alternar visualizaciones de sprites Shinies y Megas globales en el futuro.
-   **Resumen Detallado**: El menú de resumen ahora muestra una marquesina deslizante con la descripción de los objetos equipados, ideal para conocer el efecto de ítems nuevos o modificados.

## 5. Estabilidad y Corrección de Errores

-   **Sincronización de Sprites**: He detectado y corregido fallos menores en las rutas de los sprites y los nombres de archivos en formas alternativas (como Mewtwo Mega y Typhlosion Hisui), asegurando que el juego siempre encuentre el gráfico correcto.
-   **Eliminación de Crashes**: He eliminado el error "RepExp" que ocurría al interactuar con slots vacíos y he limpiado los "botones fantasma" que causaban comportamientos erráticos en el menú.
-   **Resolución 1080p**: He optimizado el escalado para pantallas modernas sin pérdida de calidad visual.

## 6. Portabilidad y Sistema de Guardado (Modo Portable)

He configurado el motor del juego para que funcione en **modo totalmente portable**:
- **Saves Locales**: A diferencia del original que guarda en carpetas ocultas del sistema (`%AppData%`), mi versión almacena las partidas directamente en la carpeta del juego (`LastSave.dat` y `Partidas Guardadas`).
- **Ventaja**: Esto facilita enormemente el respaldo de las partidas y permite llevar el juego en un dispositivo externo sin perder el progreso.

---
*He implementado todos estos cambios mediante hooks dinámicos en `preload.rb` para mantener la integridad de los scripts originales del juego.*
