package org.uvccamera.flutter;

import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.util.Log;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * VTQ — diagnóstico TEMPORAL para descubrir cómo envía el endoscopio sus botones.
 * <p>
 * 1) Vuelca e interpreta los descriptores USB (Extension Units, bTriggerSupport...).
 * 2) Consulta en bucle (GET_CUR) todos los controles de las Extension Units y
 * registra cualquier cambio de valor. Todo sale en logcat con la etiqueta "VtqDiag".
 */
/* package-private */ class VtqUsbDiagnostics {

    private static final String TAG = "VtqDiag";

    /** true: no se abre el video; la interfaz de control queda para el diagnóstico. */
    static final boolean DIAG_ONLY = true;

    private static final int CS_INTERFACE = 0x24;
    private static final int VC_EXTENSION_UNIT = 0x06;
    private static final int VS_INPUT_HEADER = 0x01;

    private static final int GET_CUR = 0x81;
    private static final int GET_LEN = 0x85;

    private final UsbDeviceConnection connection;
    private final UsbDevice device;
    private final List<int[]> controls = new ArrayList<>(); // {unitId, selector, length}
    private int vcInterface = 0;
    private volatile boolean running = true;
    private Thread thread;
    private java.io.File outDir;

    VtqUsbDiagnostics(final UsbDevice device, final UsbDeviceConnection connection) {
        this.device = device;
        this.connection = connection;
    }

    /** Carpeta donde se guardan los barridos completos (sweep_NNN.bin). */
    void setOutputDir(final java.io.File dir) {
        this.outDir = dir;
    }

    void start() {
        thread = new Thread(this::run, "VtqDiag");
        thread.setDaemon(true);
        thread.start();
    }

    void stop() {
        running = false;
    }

    private void run() {
        try {
            final byte[] raw = connection.getRawDescriptors();
            if (raw == null) {
                Log.w(TAG, "sin descriptores");
                return;
            }
            dumpHex(raw);
            final List<int[]> units = parse(raw);
            final boolean claimed = connection.claimInterface(device.getInterface(0), DIAG_ONLY);
            Log.i(TAG, "claimInterface(0) = " + claimed);
            startInterruptReader();
            probeUnits(units);
            if (DIAG_ONLY) watchStandardControls();
            // La lectura de registros ya no aportó nada; se deja apagada para
            // que el log solo muestre el análisis de los cuadros de video.
        } catch (final Exception e) {
            Log.w(TAG, "diagnóstico falló", e);
        }
    }

    // ----------------------------------------------------------- descriptores

    private void dumpHex(final byte[] raw) {
        Log.i(TAG, "descriptores: " + raw.length + " bytes");
        final var sb = new StringBuilder();
        for (int i = 0; i < raw.length; i++) {
            sb.append(String.format("%02x ", raw[i] & 0xff));
            if (i % 32 == 31) {
                Log.i(TAG, "raw " + sb);
                sb.setLength(0);
            }
        }
        if (sb.length() > 0) Log.i(TAG, "raw " + sb);
    }

    /** Devuelve {unitId, numControls, bmControls-bits...} por cada Extension Unit. */
    private List<int[]> parse(final byte[] d) {
        final List<int[]> units = new ArrayList<>();
        int currentClass = -1, currentSubclass = -1;
        int i = 0;
        while (i + 2 <= d.length) {
            final int len = d[i] & 0xff;
            final int type = d[i + 1] & 0xff;
            if (len < 2 || i + len > d.length) break;

            if (type == 0x04) { // INTERFACE
                final int number = d[i + 2] & 0xff;
                currentClass = d[i + 5] & 0xff;
                currentSubclass = d[i + 6] & 0xff;
                Log.i(TAG, "interfaz " + number + " alt " + (d[i + 3] & 0xff)
                        + " clase " + currentClass + " subclase " + currentSubclass
                        + " endpoints " + (d[i + 4] & 0xff));
                if (currentClass == 14 && currentSubclass == 1) vcInterface = number;
            } else if (type == 0x05) { // ENDPOINT
                Log.i(TAG, String.format("  endpoint 0x%02x atributos %d tamaño %d intervalo %d",
                        d[i + 2] & 0xff, d[i + 3] & 0xff, (d[i + 4] & 0xff) | ((d[i + 5] & 0xff) << 8), d[i + 6] & 0xff));
            } else if (type == CS_INTERFACE && currentClass == 14) {
                final int subtype = d[i + 2] & 0xff;
                if (currentSubclass == 1) {
                    Log.i(TAG, String.format("  VC subtipo 0x%02x id %d: %s", subtype, d[i + 3] & 0xff, hex(d, i, len)));
                    if (subtype == VC_EXTENSION_UNIT) {
                        final int unitId = d[i + 3] & 0xff;
                        final String guid = hex(d, i + 4, 16);
                        final int numControls = d[i + 20] & 0xff;
                        final int nrInPins = d[i + 21] & 0xff;
                        final int controlSize = d[i + 22 + nrInPins] & 0xff;
                        final int[] unit = new int[2 + controlSize * 8];
                        unit[0] = unitId;
                        unit[1] = numControls;
                        final var bits = new StringBuilder();
                        for (int b = 0; b < controlSize * 8; b++) {
                            final int byteVal = d[i + 23 + nrInPins + b / 8] & 0xff;
                            unit[2 + b] = (byteVal >> (b % 8)) & 1;
                            bits.append(unit[2 + b]);
                        }
                        Log.i(TAG, "  EXTENSION UNIT id " + unitId + " guid " + guid
                                + " controles " + numControls + " bmControls " + bits);
                        units.add(unit);
                    }
                } else if (currentSubclass == 2 && subtype == VS_INPUT_HEADER) {
                    Log.i(TAG, String.format("  VS INPUT HEADER endpoint 0x%02x bmInfo %d stillCaptureMethod %d "
                                    + "triggerSupport %d triggerUsage %d",
                            d[i + 6] & 0xff, d[i + 7] & 0xff, d[i + 9] & 0xff, d[i + 10] & 0xff, d[i + 11] & 0xff));
                } else if (currentSubclass == 2) {
                    Log.i(TAG, String.format("  VS subtipo 0x%02x: %s", subtype, hex(d, i, Math.min(len, 12))));
                }
            }
            i += len;
        }
        return units;
    }

    // ------------------------------------------------------------ controles XU

    private void probeUnits(final List<int[]> units) {
        for (final int[] unit : units) {
            final int unitId = unit[0];
            // Se prueban todos los selectores 1..32, estén o no marcados en bmControls.
            for (int selector = 1; selector <= Math.max(32, unit.length - 2); selector++) {
                final byte[] lenBuf = new byte[2];
                final int r = connection.controlTransfer(0xA1, GET_LEN, selector << 8,
                        (unitId << 8) | vcInterface, lenBuf, 2, 1000);
                if (selector <= 8) {
                    final byte[] info = new byte[1];
                    final int ri = connection.controlTransfer(0xA1, 0x86 /* GET_INFO */, selector << 8,
                            (unitId << 8) | vcInterface, info, 1, 1000);
                    Log.i(TAG, "XU " + unitId + " selector " + selector + " GET_LEN r=" + r + " "
                            + hex(lenBuf, 0, 2) + " GET_INFO r=" + ri + " " + hex(info, 0, 1));
                }
                if (r != 2) continue;
                final int length = (lenBuf[0] & 0xff) | ((lenBuf[1] & 0xff) << 8);
                if (length <= 0 || length > 1024) continue;
                final byte[] cur = new byte[length];
                final int rc = connection.controlTransfer(0xA1, GET_CUR, selector << 8,
                        (unitId << 8) | vcInterface, cur, length, 200);
                Log.i(TAG, "XU " + unitId + " selector " + selector + " largo " + length
                        + (rc > 0 ? " valor " + hex(cur, 0, rc) : " (GET_CUR falló: " + rc + ")"));
                if (rc > 0) controls.add(new int[]{unitId, selector, length});
            }
        }
        Log.i(TAG, "controles XU legibles: " + controls.size());
    }

    /** Lee el endpoint de interrupción de la interfaz de control y registra todo lo que llegue. */
    private void startInterruptReader() {
        final var intf = device.getInterface(0);
        android.hardware.usb.UsbEndpoint ep = null;
        for (int k = 0; k < intf.getEndpointCount(); k++) {
            if (intf.getEndpoint(k).getType() == android.hardware.usb.UsbConstants.USB_ENDPOINT_XFER_INT) {
                ep = intf.getEndpoint(k);
            }
        }
        if (ep == null) {
            Log.i(TAG, "sin endpoint de interrupción");
            return;
        }
        final var endpoint = ep;
        final Thread t = new Thread(() -> {
            Log.i(TAG, String.format("escuchando interrupción 0x%02x", endpoint.getAddress()));
            final byte[] buf = new byte[endpoint.getMaxPacketSize()];
            while (running) {
                final int r = connection.bulkTransfer(endpoint, buf, buf.length, 500);
                if (r > 0) Log.i(TAG, "INTERRUPCIÓN " + r + " bytes: " + hex(buf, 0, r));
            }
        }, "VtqDiagInt");
        t.setDaemon(true);
        t.start();
    }

    private static final int ASIC_FROM = 0x1000;
    private static final int ASIC_TO = 0x13FF;
    private static final int LEARN_SWEEPS = 4;

    /** Lee un registro del chip Sonix por el selector 1 de la XU (SET_CUR dirección, GET_CUR valor). */
    private int readAsic(final int unitId, final int addr) {
        final byte[] buf = {(byte) (addr & 0xff), (byte) (addr >> 8), 0, (byte) 0xFF};
        if (connection.controlTransfer(0x21, 0x01 /* SET_CUR */, 1 << 8, (unitId << 8) | vcInterface, buf, 4, 200) != 4) {
            return -1;
        }
        if (connection.controlTransfer(0xA1, GET_CUR, 1 << 8, (unitId << 8) | vcInterface, buf, 4, 200) != 4) {
            return -1;
        }
        return buf[2] & 0xff;
    }

    /** Zonas donde aparecieron cambios al presionar los botones. */
    private static final int[][] WATCH = {{0x11D8, 0x11E7}, {0x12D0, 0x12DF}};

    private void poll() throws InterruptedException {
        final int unitId = controls.isEmpty() ? 3 : controls.get(0)[0];
        final List<Integer> addrs = new ArrayList<>();
        for (final int[] r : WATCH) for (int a = r[0]; a <= r[1]; a++) addrs.add(a);
        final int[] last = new int[addrs.size()];
        Arrays.fill(last, Integer.MIN_VALUE);

        Log.i(TAG, "LISTO: vigilando " + addrs.size() + " registros rápido. Presiona los botones.");
        long sweeps = 0;
        final long t0 = System.currentTimeMillis();
        while (running) {
            final var changes = new StringBuilder();
            for (int k = 0; k < addrs.size(); k++) {
                final int v = readAsic(unitId, addrs.get(k));
                if (v < 0) continue;
                if (last[k] != Integer.MIN_VALUE && last[k] != v) {
                    changes.append(String.format("0x%04x:%02x->%02x  ", addrs.get(k), last[k], v));
                }
                last[k] = v;
            }
            if (changes.length() > 0) Log.i(TAG, "CAMBIO " + changes);
            if (++sweeps == 20) {
                Log.i(TAG, "ritmo: " + (System.currentTimeMillis() - t0) / 20 + " ms por lectura");
            }
        }
        Log.i(TAG, "diagnóstico detenido");
    }

    // ------------------------------------------- controles estándar UVC (PU / CT)

    /** {unidad, selector, nombre}: Camera Terminal id 1 y Processing Unit id 2 según el descriptor. */
    private static final Object[][] STD = {
            {1, 0x02, "CT modo exposición auto", 1}, {1, 0x03, "CT prioridad exposición", 1},
            {1, 0x04, "CT tiempo exposición", 4},
            {2, 0x01, "PU compensación contraluz", 2}, {2, 0x02, "PU brillo", 2}, {2, 0x03, "PU contraste", 2},
            {2, 0x04, "PU ganancia", 2}, {2, 0x05, "PU frecuencia de red", 1}, {2, 0x06, "PU tono", 2},
            {2, 0x07, "PU saturación", 2}, {2, 0x08, "PU nitidez", 2}, {2, 0x09, "PU gamma", 2},
            {2, 0x0A, "PU temperatura de blanco", 2}, {2, 0x0B, "PU blanco automático", 1},
    };

    private void watchStandardControls() {
        final int n = STD.length + controls.size();
        final byte[][] last = new byte[n][];
        long loops = 0;
        final long t0 = System.currentTimeMillis();
        Log.i(TAG, "VIGILANDO controles estándar y XU. Presiona los botones.");
        while (running) {
            final var sb = new StringBuilder();
            for (int k = 0; k < n; k++) {
                final int unit, sel, len;
                final String name;
                if (k < STD.length) {
                    unit = (int) STD[k][0];
                    sel = (int) STD[k][1];
                    name = (String) STD[k][2];
                    len = (int) STD[k][3];
                } else {
                    final int[] c = controls.get(k - STD.length);
                    unit = c[0];
                    sel = c[1];
                    len = c[2];
                    name = "XU sel " + sel;
                }
                final byte[] cur = new byte[len];
                final int r = connection.controlTransfer(0xA1, GET_CUR, sel << 8, (unit << 8) | vcInterface, cur, len, 200);
                if (r <= 0) {
                    if (loops == 0) Log.i(TAG, "sin lectura: " + name + " (r=" + r + ")");
                    continue;
                }
                final byte[] now = Arrays.copyOf(cur, r);
                if (loops == 0) Log.i(TAG, "inicial " + name + ": " + hex(now, 0, now.length));
                if (last[k] != null && !Arrays.equals(last[k], now)) {
                    sb.append(name).append(": ").append(hex(last[k], 0, last[k].length)).append("-> ")
                            .append(hex(now, 0, now.length)).append(" | ");
                }
                last[k] = now;
            }
            if (sb.length() > 0) Log.i(TAG, "CAMBIO " + sb);
            if (++loops == 100) Log.i(TAG, "ritmo: " + (System.currentTimeMillis() - t0) / 100 + " ms por vuelta");
        }
    }

    // ------------------------------------------------- vigilancia de candidatas

    /** Direcciones que cambiaron con el botón 2 sujeto y volvieron al soltarlo. */
    private static final int[] CANDIDATES = {0x077c, 0x8723, 0x894f, 0xc185, 0xca17, 0xcd04, 0xce8c};

    private void watchCandidates() {
        final int unitId = controls.isEmpty() ? 3 : controls.get(0)[0];
        final int[] last = new int[CANDIDATES.length];
        Arrays.fill(last, Integer.MIN_VALUE);
        long loops = 0;
        final long t0 = System.currentTimeMillis();
        Log.i(TAG, "VIGILANDO candidatas. Presiona el botón 2 varias veces.");
        while (running) {
            final var sb = new StringBuilder();
            for (int k = 0; k < CANDIDATES.length; k++) {
                final int v = readAsic(unitId, CANDIDATES[k]);
                if (v < 0) continue;
                if (last[k] != Integer.MIN_VALUE && last[k] != v) {
                    sb.append(String.format("0x%04x:%02x->%02x  ", CANDIDATES[k], last[k], v));
                }
                last[k] = v;
            }
            if (sb.length() > 0) Log.i(TAG, "CAMBIO " + sb);
            if (++loops == 200) {
                Log.i(TAG, "ritmo: " + (System.currentTimeMillis() - t0) / 200 + " ms por vuelta");
            }
        }
    }

    // ------------------------------------------------------ barrido completo

    /**
     * Lee las 65536 direcciones del chip una y otra vez. Cada barrido se guarda en
     * outDir/sweep_NNN.bin como 65536 valores de 16 bits (little endian): 0..255 es el
     * valor leído y 0xFFFF significa que la dirección no se pudo leer.
     */
    private void fullSweeps() throws Exception {
        final int unitId = controls.isEmpty() ? 3 : controls.get(0)[0];
        final var fmt = new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US);
        for (int n = 1; running; n++) {
            final long t0 = System.currentTimeMillis();
            final byte[] out = new byte[65536 * 2];
            int readable = 0, pagesSkipped = 0;
            for (int page = 0; page < 256 && running; page++) {
                if (readAsic(unitId, page << 8) < 0) {
                    pagesSkipped++;
                    for (int k = 0; k < 256; k++) {
                        out[((page << 8) + k) * 2] = (byte) 0xFF;
                        out[((page << 8) + k) * 2 + 1] = (byte) 0xFF;
                    }
                    continue;
                }
                for (int k = 0; k < 256; k++) {
                    final int addr = (page << 8) | k;
                    final int v = readAsic(unitId, addr);
                    out[addr * 2] = (byte) (v < 0 ? 0xFF : v);
                    out[addr * 2 + 1] = (byte) (v < 0 ? 0xFF : 0);
                    if (v >= 0) readable++;
                }
                if (page % 32 == 31) {
                    Log.i(TAG, "barrido " + n + ": página " + (page + 1) + "/256");
                }
            }
            final long t1 = System.currentTimeMillis();
            final var file = new java.io.File(outDir, String.format(java.util.Locale.US, "sweep_%03d.bin", n));
            try (var fos = new java.io.FileOutputStream(file)) {
                fos.write(out);
            }
            Log.i(TAG, String.format(java.util.Locale.US,
                    "BARRIDO %d: %s -> %s (%d s), legibles %d, páginas sin lectura %d, archivo %s",
                    n, fmt.format(t0), fmt.format(t1), (t1 - t0) / 1000, readable, pagesSkipped, file.getName()));
        }
    }

    // ------------------------------------------------------- cuadros de video

    private String lastHeaderSig;
    private String lastTrailer;
    private int frames;
    private long frameBytes;
    private long statsSince = System.currentTimeMillis();
    private int minSize = Integer.MAX_VALUE, maxSize;

    /** Analiza cada cuadro MJPEG crudo: cabecera, segmentos APP/COM y bytes tras el final. */
    void onFrame(final java.nio.ByteBuffer frame) {
        final int n = frame.remaining();
        final byte[] b = new byte[n];
        frame.get(b);
        frames++;
        frameBytes += n;
        minSize = Math.min(minSize, n);
        maxSize = Math.max(maxSize, n);

        if (n < 4 || (b[0] & 0xff) != 0xFF || (b[1] & 0xff) != 0xD8) {
            if (frames < 5) Log.i(TAG, "cuadro no JPEG, " + n + " bytes: " + hex(b, 0, 32));
            return;
        }

        // Cabecera: marcadores y largos hasta SOS; contenido de APPn/COM.
        final var sig = new StringBuilder();
        final var extra = new StringBuilder();
        final java.util.zip.CRC32 crc = new java.util.zip.CRC32();
        int i = 2;
        while (i + 4 <= n && (b[i] & 0xff) == 0xFF) {
            final int marker = b[i + 1] & 0xff;
            final int len = ((b[i + 2] & 0xff) << 8) | (b[i + 3] & 0xff);
            sig.append(String.format("%02x:%d ", marker, len));
            if ((marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE) {
                extra.append(String.format("[%02x] %s ", marker, hex(b, i + 4, Math.min(len - 2, 48))));
            }
            if (marker != 0xDA) crc.update(b, i, Math.min(len + 2, n - i));
            if (marker == 0xDA) break;
            i += 2 + len;
        }
        final String headerSig = sig + String.format("crc=%08x", crc.getValue());
        if (!headerSig.equals(lastHeaderSig)) {
            Log.i(TAG, "CABECERA JPEG (cuadro " + frames + ", " + n + " bytes): " + headerSig
                    + (extra.length() > 0 ? " extra: " + extra : ""));
            lastHeaderSig = headerSig;
        }

        // Bytes después del último FFD9 (fin de imagen).
        int eoi = -1;
        for (int k = n - 2; k >= Math.max(0, n - 4096); k--) {
            if ((b[k] & 0xff) == 0xFF && (b[k + 1] & 0xff) == 0xD9) {
                eoi = k;
                break;
            }
        }
        final String trailer = eoi < 0 ? "sin FFD9 al final"
                : (n - eoi - 2) + " bytes: " + hex(b, eoi + 2, Math.min(n - eoi - 2, 64));
        if (!trailer.equals(lastTrailer)) {
            Log.i(TAG, "FINAL JPEG (cuadro " + frames + "): " + trailer);
            lastTrailer = trailer;
        }

        final long now = System.currentTimeMillis();
        if (now - statsSince >= 5000) {
            Log.i(TAG, String.format("cuadros: %.1f fps, tamaño %d-%d bytes",
                    frames * 1000.0 / (now - statsSince), minSize, maxSize));
            frames = 0;
            frameBytes = 0;
            minSize = Integer.MAX_VALUE;
            maxSize = 0;
            statsSince = now;
        }
    }

    private static String hex(final byte[] b, final int from, final int len) {
        final var sb = new StringBuilder();
        for (int i = from; i < from + len && i < b.length; i++) sb.append(String.format("%02x ", b[i] & 0xff));
        return sb.toString();
    }
}
