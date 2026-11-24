# Mis finanzas

Aplicación Flutter para registrar ingresos, gastos y ahorros de forma sencilla. Funciona en Android, iOS y navegadores web.

## Ejecutar

Con Flutter instalado, desde la carpeta del proyecto:

```powershell
flutter pub get
flutter run -d chrome
```

Para Android, conecta un dispositivo o inicia un emulador y ejecuta `flutter run`. Para compilar y ejecutar en iPhone se necesita un Mac con Xcode y la configuración de firma de Apple correspondiente.

## Publicación web

En GitHub, selecciona **Settings > Pages > Build and deployment > Source > GitHub Actions**. Los cambios enviados a la rama `main` ejecutan el flujo de `.github/workflows/deploy.yml` y publican la aplicación en `https://franzisko.github.io/finanzas-personales/`. El flujo también puede iniciarse manualmente desde la pestaña **Actions**.

La ruta `/finanzas-personales/` del comando de compilación corresponde al nombre del repositorio; si se cambia, actualízala en el flujo. Para usar la aplicación en iPhone, abre la dirección en Safari y selecciona **Compartir > Añadir a pantalla de inicio**. El funcionamiento sin conexión no está garantizado.

## Uso

- Selecciona un mes y añade un ingreso o gasto con concepto y monto. La fecha es automática y se puede cambiar dentro del mes seleccionado.
- Marca «Repetir cada mes» al añadir un gasto. Se registra el gasto actual y, en los meses siguientes, aparece como pendiente hasta que lo confirmes. En Opciones puedes dejar de repetirlo; los pagos ya registrados se conservan. Editar un pago recurrente solo cambia ese pago.
- El balance es ingresos menos gastos confirmados del mes. Los pendientes no se incluyen hasta confirmarlos. La comparación aparece si hay movimientos en el mes anterior.
- Los ahorros son un monto total que se actualiza manualmente; no modifica el balance ni crea movimientos.
- Los importes se expresan en euros, con hasta dos decimales.

## Datos y copias

Los datos se guardan localmente, sin cuenta ni sincronización. Cada dispositivo y navegador tiene sus propios datos. Al borrar los datos del navegador o desinstalar la aplicación, podrías perderlos.

En Opciones > Copia de seguridad, selecciona «Guardar archivo» para guardar una copia `.txt`. En la web, el navegador inicia una descarga; en Android e iOS puedes seleccionar dónde guardarla. Para restaurarla, selecciona «Restaurar > Elegir archivo» y escoge la copia. También puedes seguir copiando y pegando el texto. Restaurar reemplaza todos los datos existentes, previa confirmación. El archivo y el portapapeles contienen información financiera: guárdalos en un lugar privado. En la web, copiar al portapapeles requiere HTTPS o localhost y permiso del navegador.

## Validación

```powershell
flutter analyze
flutter test
flutter build web
```
