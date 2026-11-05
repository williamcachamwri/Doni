# Doni

[English](../../README.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md) · **Español** ·
[Français](README.fr.md) · [Русский](README.ru.md) · [العربية](README.ar.md)


Un reproductor de música para iPhone que toca lo que ya tienes en Telegram: los canales que sigues y
Saved Messages como biblioteca propia. Sin servidores detrás, sin registro, sin enviar datos a ningún lado.

<table>
  <tr>
    <td><img src="../screenshots/home.jpg" width="220"></td>
    <td><img src="../screenshots/now-playing.jpg" width="220"></td>
    <td><img src="../screenshots/lock-screen.jpg" width="220"></td>
    <td><img src="../screenshots/playlist.jpg" width="220"></td>
  </tr>
</table>

## Qué hace

- **Empieza ya y descarga mientras suena.** El archivo se pide en rangos de bytes alrededor de la
  posición: saltar a 3:40 pide la parte de 3:40, no el archivo entero.
- **Recuerda lo que pidió.** Los trozos se quedan en el teléfono aunque mates la app. Lo que ya
  escuchaste completo funciona sin red.
- **Cloud Music es Saved Messages.** Subir un archivo lo manda a tu propio chat y borra la copia local;
  si lo borras en Telegram, desaparece de la app.
- **Letras con tiempo** de lrclib, NetEase, AMLL y QQ Music. El verso que suena ocupa el título en la
  pantalla de bloqueo y en la Dynamic Island.
- **Carátulas** de la etiqueta del archivo o de la miniatura de Telegram; si Telegram aún no la generó,
  se vuelve a pedir unas cuantas veces.
- **Caché con tope.** Tú fijas el límite (2 GiB por defecto); se liberan primero las canciones menos
  escuchadas y nunca la que está sonando.
- Seis idiomas en la interfaz; las cadenas del código están en vietnamita.

## Por qué Telegram

Porque la biblioteca ya está ahí. Cada canción es un mensaje con un archivo, y cada archivo lleva un
`file_unique_id` que significa los mismos bytes en cualquier base de datos. Así «¿ya la tengo?» y «¿por
dónde iba?» los resuelve el protocolo, no un servidor que yo tenga que mantener y que lea tus datos.
TDLib hace la red: acceso, reintentos, descargas, caché de archivos, redirecciones del CDN.

## Cómo es el streaming de verdad

- `downloadFile` acepta offset y límite, pero el límite no corta la descarga: TDLib sigue hasta que lo
  cancelan, así que la app cierra cada ventana cuando ya tiene bastante.
- `getFileDownloadedPrefixSize` dice cuántos bytes hay listos en *cualquier* offset. Eso es la máscara
  de preparación, no un «terminado o no», y es lo que hace útil un archivo a medias.
- Los trozos miden 64 KiB. La ventana va unos megabytes por delante y se mueve cuando se gastó la mitad.
- AVFoundation pide bytes por `AVAssetResourceLoaderDelegate`; abre con una sonda de 2 bytes y rechaza
  respuestas más largas de lo que pidió.
- Lo que está fuera de la ventana lista es basura. Nada llega al decodificador sin la confirmación de
  TDLib, y por eso al perder la red la música se detiene en lugar de emitir ruido.

## Compilar

Hace falta iOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), CMake, Python 3 y un
`api_id`/`api_hash` de [my.telegram.org](https://my.telegram.org).

```sh
make vendor       # compila TDLib y OpenSSL (unos 20 min la primera vez)
make project      # genera Doni.xcodeproj
cp Config/Tdlib.example.xcconfig Config/Tdlib.xcconfig   # tus datos; el archivo no se sube
make build        # aviso es error
make device && make install
```

## Publicar

Una versión, dos números, los dos en `project.yml` y se cambian juntos. `MARKETING_VERSION` es la que
muestra «Información» y la que debe coincidir con la etiqueta; `CURRENT_PROJECT_VERSION` es el número de
compilación que lleva la misma versión en sus dígitos: `90 | mayor | menor | parche`, así que `9010000`
es 1.0.0. Las notas de versión se escriben una vez en `RELEASE_NOTES.md`, en dos idiomas y con igual
cantidad de líneas.

## Límites

- Firma con equipo gratuito: 3 dispositivos y certificado que muere a los 7 días.
- El IPA de CI no está firmado; hay que volver a firmarlo con tu propio equipo.
- Sin CarPlay por ahora: hace falta el permiso `carplay-audio`, o sea cuenta de pago.
- Las letras vienen de fuentes públicas. Si nadie escribió la de una canción, la app lo dice en vez de
  mostrar una página vacía.
- Comprobar actualizaciones informa y abre la página de la versión; no instala nada.

## Licencia y créditos

GPL-3.0 ([LICENSE](../../LICENSE)): la pantalla de letras y varias vistas salen de
[MeloX](https://github.com/youshen2/MeloX), que es GPLv3. **TDLib** (BSL 1.0), **OpenSSL** (Apache-2.0),
**SQLite** para la biblioteca y las listas, y **Telegram-iOS** (GPL-2.0) solo para medir separaciones y
colores: no hay ni una línea de su código aquí.

Doni no está afiliado ni autorizado por Telegram ni por ninguna discográfica. Abre archivos que ya
están en tu cuenta.

Contacto: Telegram [@w1lliamcachamwri](https://t.me/w1lliamcachamwri) ·
[github.com/williamcachamwri/Doni](https://github.com/williamcachamwri/Doni)

