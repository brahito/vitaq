package org.uvccamera.flutter;

import com.serenegiant.usb.IFrameCallback;

import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicReference;

/**
 * VTQ: callback de cuadros que queda puesto durante toda una grabación.
 * <p>
 * libuvccamera deja de mandar cuadros al video si se cambia el callback de
 * cuadros mientras graba, así que las fotos tomadas grabando no ponen ni quitan
 * su propio callback: se piden aquí y se responden con el siguiente cuadro.
 */
/* package-private */ class UvcCameraRecordingFrameTap implements IFrameCallback {

    private final AtomicReference<IFrameCallback> pending = new AtomicReference<>();

    /**
     * Pide el siguiente cuadro para [picture]. Devuelve false si ya había una foto en curso.
     */
    boolean request(final IFrameCallback picture) {
        return pending.compareAndSet(null, picture);
    }

    /**
     * Quita la foto pendiente, si la hay, para avisarle que no llegará.
     */
    IFrameCallback cancel() {
        return pending.getAndSet(null);
    }

    @Override
    public void onFrame(final ByteBuffer frame) {
        final var picture = pending.getAndSet(null);
        if (picture != null) {
            picture.onFrame(frame);
        }
    }

}
