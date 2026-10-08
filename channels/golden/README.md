# Golden Channel — Stremio TV

Canal cinematográfico **no oficial**, inspirado en Golden México (izzi 607) y en títulos consultados para el periodo 2026-09-24 a 2026-10-22 (America/Mexico_City).

## Contenido
- `golden-channel.json`: catálogo Stremio TV con 284 películas, cada una con identificador IMDb; reúne películas observadas en la ventana consultada con títulos complementarios de géneros compatibles (comedia, acción, aventura, drama, clásicos).
- `golden-channel-cover.svg`: portada vertical independiente del póster de la película.
- El catálogo no contiene archivos audiovisuales, fuentes pirateadas, ni URLs de streams. La disponibilidad depende de los add-ons instalados.
- Es **una rotación al estilo Golden**, no una retransmisión oficial ni un EPG minuto a minuto de izzi. Las películas adicionales no se presentan como emisiones verificadas del canal.

## Importación en Debrify / Stremio TV
1. Abrir **Stremio TV** → **Importar** → **Desde URL**.
2. Introducir la URL RAW de este mismo archivo:
   `https://raw.githubusercontent.com/Jorgeprdz/debrify/feature/stremio-tv-golden-channel/channels/golden/golden-channel.json`
3. Confirmar que aparece **Golden Channel** en los canales locales; se puede poner en favoritos y reordenar.
4. Si se actualiza el catálogo, usar **Actualizar desde URL**. Importar el mismo nombre desde URL actualiza su entrada actual y conserva orden e ID.

## Portada: corrección del problema de Blockbuster
El JSON ahora incluye `"cover"` con la URL RAW del SVG, mientras cada película conserva su `"poster"`. La rama incorpora cambios de código para:
- preservar `cover` en importación y actualización;
- hidratar `StremioTvChannel.coverUrl`;
- pintar esa portada en las tarjetas del sintonizador y el selector de canales con `flutter_svg`;
- mostrar el nombre sin el prefijo `Local:` cuando el catálogo tiene portada;
- dejar intactas las portadas de las películas para la vista de reproducción.

**Advertencia importante:** versiones de la aplicación anteriores a este PR pueden importar la lista de películas, pero *ignorarán la portada independiente*. La imagen requiere una versión compilada que incorpore la modificación. No se afirma que esté funcionando ya en el Chromecast.

## No modificar
Este paquete no altera `Para Ti`, perfiles, otros catálogos ni el feed JSON remoto anterior. No cambia las funciones Cast existentes.

## QA
- Validación estática de JSON, IDs IMDb únicos, URL de `cover` y consistencia básica del parche.
- Test unitario del modelo en `test/stremio_tv_channel_cover_test.dart`.
- Pendiente: `flutter test` y comprobación del render SVG/HTTP en Chromecast HD y 4K, además de la resolución real de streams y el refresh desde URL.
