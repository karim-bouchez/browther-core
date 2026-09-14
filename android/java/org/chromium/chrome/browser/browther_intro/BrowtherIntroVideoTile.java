/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.graphics.Bitmap;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.SurfaceTexture;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES20;
import android.opengl.GLUtils;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.view.Surface;
import android.view.TextureView;

import org.chromium.base.Log;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.List;

/**
 * La vignette « vidéo » : le voile suit les personnes, image par image.
 *
 * <p>Ici le flou ne peut pas être posé par-dessus — on ne peut pas afficher deux fois la même
 * couche vidéo. Il est donc calculé <b>dans le flux</b> (ONBOARDING-SPEC.md § 4.3) : la vidéo est
 * décodée dans une texture, et un shader rejoue le compositeur du moteur sur chaque image — flou
 * gaussien sur toute l'image (rayon {@code max(25, 4 %)} en pixels du média, bords étirés), masque
 * des contours adouci de 10 px du média, composition. Le contour est choisi par <b>l'horodatage de
 * l'image décodée</b> : le voile ne peut pas prendre une image de retard sur la personne qu'il
 * couvre.
 *
 * <p>Lecture en boucle, muette, sans commandes : c'est une illustration, pas un lecteur.
 */
final class BrowtherIntroVideoTile extends TextureView implements TextureView.SurfaceTextureListener {
    private static final String TAG = "BrowtherIntro";

    /** Le flou travaille au quart de la taille du média (225 px de large pour 900). */
    private static final int BLUR_DOWNSCALE = 4;

    private final Context mContext;
    private final BrowtherIntroMedia.Track mTrack;
    private volatile BrowtherIntroMedia.Veil mVeil =
            new BrowtherIntroMedia.Veil(BrowtherIntroMedia.VeilKind.EVERYTHING, null);
    private Renderer mRenderer;
    private boolean mWindowVisible = true;

    BrowtherIntroVideoTile(Context context, BrowtherIntroMedia.Track track) {
        super(context);
        mContext = context;
        mTrack = track;
        setOpaque(true);
        setSurfaceTextureListener(this);
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    void setVeil(BrowtherIntroMedia.Veil veil) {
        mVeil = veil;
    }

    @Override
    public void onSurfaceTextureAvailable(SurfaceTexture surface, int width, int height) {
        mRenderer = new Renderer(surface, width, height);
        mRenderer.setPaused(!mWindowVisible);
    }

    @Override
    public void onSurfaceTextureSizeChanged(SurfaceTexture surface, int width, int height) {
        if (mRenderer != null) mRenderer.resize(width, height);
    }

    @Override
    public boolean onSurfaceTextureDestroyed(SurfaceTexture surface) {
        if (mRenderer != null) {
            mRenderer.release();
            mRenderer = null;
            // Le rendu libère lui-même la SurfaceTexture, APRÈS sa surface EGL.
            return false;
        }
        return true;
    }

    @Override
    public void onSurfaceTextureUpdated(SurfaceTexture surface) {}

    @Override
    protected void onWindowVisibilityChanged(int visibility) {
        super.onWindowVisibilityChanged(visibility);
        // Application en arrière-plan : le décodeur s'arrête, il ne tourne pas pour personne.
        mWindowVisible = visibility == VISIBLE;
        if (mRenderer != null) mRenderer.setPaused(!mWindowVisible);
    }

    // =====================================================================================
    // Rendu : décodage MediaCodec → texture externe → flou séparable → composition.
    // =====================================================================================

    private static final String VERTEX =
            "attribute vec4 aPosition;\n"
                    + "attribute vec2 aTexCoord;\n"
                    + "uniform mat4 uTexMatrix;\n"
                    + "varying vec2 vTexCoord;\n"
                    + "varying vec2 vUv;\n"
                    + "void main() {\n"
                    + "  gl_Position = aPosition;\n"
                    + "  vTexCoord = (uTexMatrix * vec4(aTexCoord, 0.0, 1.0)).xy;\n"
                    + "  vUv = aTexCoord;\n"
                    + "}\n";

    /** Réduction au quart, sur quatre prélèvements : un seul scintillerait. */
    private static final String DOWNSAMPLE =
            "#extension GL_OES_EGL_image_external : require\n"
                    + "precision mediump float;\n"
                    + "uniform samplerExternalOES uVideo;\n"
                    + "uniform vec2 uStep;\n"
                    + "varying vec2 vTexCoord;\n"
                    + "void main() {\n"
                    + "  gl_FragColor = 0.25 * (texture2D(uVideo, vTexCoord + vec2(-uStep.x, -uStep.y))\n"
                    + "      + texture2D(uVideo, vTexCoord + vec2(uStep.x, -uStep.y))\n"
                    + "      + texture2D(uVideo, vTexCoord + vec2(-uStep.x, uStep.y))\n"
                    + "      + texture2D(uVideo, vTexCoord + vec2(uStep.x, uStep.y)));\n"
                    + "}\n";

    private static final int TAPS = 15;

    /** Gaussien séparable, prélèvements bilinéaires appariés. */
    private static final String BLUR =
            "precision mediump float;\n"
                    + "uniform sampler2D uTexture;\n"
                    + "uniform vec2 uDirection;\n"
                    + "uniform float uWeights[" + TAPS + "];\n"
                    + "uniform float uOffsets[" + TAPS + "];\n"
                    + "varying vec2 vUv;\n"
                    + "void main() {\n"
                    + "  vec4 color = texture2D(uTexture, vUv) * uWeights[0];\n"
                    + "  for (int i = 1; i < " + TAPS + "; i++) {\n"
                    + "    vec2 offset = uDirection * uOffsets[i];\n"
                    + "    color += (texture2D(uTexture, vUv + offset)\n"
                    + "        + texture2D(uTexture, vUv - offset)) * uWeights[i];\n"
                    + "  }\n"
                    + "  gl_FragColor = color;\n"
                    + "}\n";

    /** L'image nette dessous, la floutée au travers du masque. */
    private static final String COMPOSITE =
            "#extension GL_OES_EGL_image_external : require\n"
                    + "precision mediump float;\n"
                    + "uniform samplerExternalOES uVideo;\n"
                    + "uniform sampler2D uBlurred;\n"
                    + "uniform sampler2D uMask;\n"
                    + "varying vec2 vTexCoord;\n"
                    + "varying vec2 vUv;\n"
                    + "void main() {\n"
                    + "  vec3 sharp = texture2D(uVideo, vTexCoord).rgb;\n"
                    + "  vec3 blurred = texture2D(uBlurred, vUv).rgb;\n"
                    // Le masque vient d'un Bitmap : sa première ligne est en haut.
                    + "  float mask = texture2D(uMask, vec2(vUv.x, 1.0 - vUv.y)).a;\n"
                    + "  gl_FragColor = vec4(mix(sharp, blurred, mask), 1.0);\n"
                    + "}\n";

    private static final int GL_TEXTURE_EXTERNAL_OES = 0x8D65;

    private final class Renderer implements SurfaceTexture.OnFrameAvailableListener {
        private final HandlerThread mThread = new HandlerThread("BrowtherIntroVideo");
        private final Handler mHandler;
        private final SurfaceTexture mOutput;
        private final float[] mTexMatrix = new float[16];
        private final float[] mIdentity = new float[16];
        private final float[] mWeights = new float[TAPS];
        private final float[] mOffsets = new float[TAPS];
        private final Paint mMaskPaint = new Paint();
        private final Path mMaskPath = new Path();

        private int mWidth;
        private int mHeight;
        private EGLDisplay mDisplay = EGL14.EGL_NO_DISPLAY;
        private EGLContext mEglContext = EGL14.EGL_NO_CONTEXT;
        private EGLSurface mEglSurface = EGL14.EGL_NO_SURFACE;
        private FloatBuffer mQuad;
        private int mDownsampleProgram;
        private int mBlurProgram;
        private int mCompositeProgram;
        private int mVideoTexture;
        private final int[] mFboTextures = new int[2];
        private final int[] mFbos = new int[2];
        private int mMaskTexture;
        private int mSmallWidth;
        private int mSmallHeight;
        private Bitmap mMaskBitmap;
        private int mMaskIndex = Integer.MIN_VALUE;
        private BrowtherIntroMedia.Veil mMaskVeil;
        private SurfaceTexture mVideoSurfaceTexture;
        private Surface mVideoSurface;
        private Decoder mDecoder;
        private volatile boolean mReleased;

        Renderer(SurfaceTexture output, int width, int height) {
            mOutput = output;
            mWidth = width;
            mHeight = height;
            mThread.start();
            mHandler = new Handler(mThread.getLooper());
            android.opengl.Matrix.setIdentityM(mIdentity, 0);
            mHandler.post(this::init);
        }

        void resize(int width, int height) {
            mHandler.post(
                    () -> {
                        mWidth = width;
                        mHeight = height;
                    });
        }

        void setPaused(boolean paused) {
            mHandler.post(
                    () -> {
                        if (mDecoder != null) mDecoder.setPaused(paused);
                    });
        }

        void release() {
            mReleased = true;
            mHandler.post(
                    () -> {
                        if (mDecoder != null) mDecoder.shutdown();
                        mDecoder = null;
                        teardownGl();
                        mOutput.release();
                        mThread.quitSafely();
                    });
        }

        private void init() {
            try {
                setupEgl();
                setupGl();
            } catch (RuntimeException e) {
                // Pas de plan B silencieux : la vignette reste sombre et la panne se lit au journal.
                Log.e(TAG, "Voile vidéo : initialisation GL impossible", e);
                teardownGl();
                return;
            }
            mVideoSurfaceTexture = new SurfaceTexture(mVideoTexture);
            mVideoSurfaceTexture.setOnFrameAvailableListener(this, mHandler);
            mVideoSurface = new Surface(mVideoSurfaceTexture);
            mDecoder = new Decoder(mContext, mVideoSurface);
            mDecoder.start();
        }

        @Override
        public void onFrameAvailable(SurfaceTexture surfaceTexture) {
            if (mReleased || mEglSurface == EGL14.EGL_NO_SURFACE) return;
            mVideoSurfaceTexture.updateTexImage();
            mVideoSurfaceTexture.getTransformMatrix(mTexMatrix);
            double seconds = mDecoder == null ? 0 : mDecoder.mediaSeconds(
                    mVideoSurfaceTexture.getTimestamp());
            updateMask(seconds);
            draw();
        }

        // -------------------- EGL / GL --------------------

        private void setupEgl() {
            mDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
            int[] version = new int[2];
            if (!EGL14.eglInitialize(mDisplay, version, 0, version, 1)) {
                throw new RuntimeException("eglInitialize");
            }
            int[] attributes = {
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                EGL14.EGL_NONE
            };
            EGLConfig[] configs = new EGLConfig[1];
            int[] count = new int[1];
            if (!EGL14.eglChooseConfig(mDisplay, attributes, 0, configs, 0, 1, count, 0)
                    || count[0] == 0) {
                throw new RuntimeException("eglChooseConfig");
            }
            mEglContext =
                    EGL14.eglCreateContext(
                            mDisplay,
                            configs[0],
                            EGL14.EGL_NO_CONTEXT,
                            new int[] {EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE},
                            0);
            if (mEglContext == EGL14.EGL_NO_CONTEXT) throw new RuntimeException("eglCreateContext");
            mEglSurface =
                    EGL14.eglCreateWindowSurface(
                            mDisplay, configs[0], mOutput, new int[] {EGL14.EGL_NONE}, 0);
            if (mEglSurface == EGL14.EGL_NO_SURFACE) {
                throw new RuntimeException("eglCreateWindowSurface");
            }
            if (!EGL14.eglMakeCurrent(mDisplay, mEglSurface, mEglSurface, mEglContext)) {
                throw new RuntimeException("eglMakeCurrent");
            }
        }

        private void setupGl() {
            float[] quad = {
                -1f, -1f, 0f, 0f,
                1f, -1f, 1f, 0f,
                -1f, 1f, 0f, 1f,
                1f, 1f, 1f, 1f,
            };
            mQuad =
                    ByteBuffer.allocateDirect(quad.length * 4)
                            .order(ByteOrder.nativeOrder())
                            .asFloatBuffer();
            mQuad.put(quad).position(0);

            mDownsampleProgram = program(VERTEX, DOWNSAMPLE);
            mBlurProgram = program(VERTEX, BLUR);
            mCompositeProgram = program(VERTEX, COMPOSITE);

            int[] textures = new int[1];
            GLES20.glGenTextures(1, textures, 0);
            mVideoTexture = textures[0];
            GLES20.glBindTexture(GL_TEXTURE_EXTERNAL_OES, mVideoTexture);
            parameters(GL_TEXTURE_EXTERNAL_OES);

            mSmallWidth = Math.max(1, BrowtherIntroMedia.VIDEO_WIDTH / BLUR_DOWNSCALE);
            mSmallHeight = Math.max(1, Math.round(506f / BLUR_DOWNSCALE));
            GLES20.glGenTextures(2, mFboTextures, 0);
            GLES20.glGenFramebuffers(2, mFbos, 0);
            for (int i = 0; i < 2; i++) {
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, mFboTextures[i]);
                parameters(GLES20.GL_TEXTURE_2D);
                GLES20.glTexImage2D(
                        GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, mSmallWidth, mSmallHeight, 0,
                        GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null);
                GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, mFbos[i]);
                GLES20.glFramebufferTexture2D(
                        GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0, GLES20.GL_TEXTURE_2D,
                        mFboTextures[i], 0);
                if (GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
                        != GLES20.GL_FRAMEBUFFER_COMPLETE) {
                    throw new RuntimeException("framebuffer incomplet");
                }
            }
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0);

            mMaskBitmap = Bitmap.createBitmap(mSmallWidth, mSmallHeight, Bitmap.Config.ARGB_8888);
            GLES20.glGenTextures(1, textures, 0);
            mMaskTexture = textures[0];
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, mMaskTexture);
            parameters(GLES20.GL_TEXTURE_2D);
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, mMaskBitmap, 0);

            gaussianWeights(
                    BrowtherIntroMedia.blurRadius(BrowtherIntroMedia.VIDEO_WIDTH, 506)
                            / BLUR_DOWNSCALE);
        }

        /**
         * Poids du gaussien, rayon 3σ, prélèvements appariés : deux texels voisins lus d'un seul
         * prélèvement bilinéaire, placé à leur barycentre.
         */
        private void gaussianWeights(float sigma) {
            int radius = (int) Math.ceil(sigma * 3);
            float[] discrete = new float[radius + 2];
            float sum = 0;
            for (int i = 0; i <= radius; i++) {
                discrete[i] = (float) Math.exp(-(i * i) / (2 * sigma * sigma));
                sum += i == 0 ? discrete[i] : 2 * discrete[i];
            }
            for (int i = 0; i <= radius; i++) discrete[i] /= sum;
            mWeights[0] = discrete[0];
            mOffsets[0] = 0;
            int tap = 1;
            for (int i = 1; i <= radius && tap < TAPS; i += 2, tap++) {
                float a = discrete[i];
                float b = discrete[i + 1];
                mWeights[tap] = a + b;
                mOffsets[tap] = (a + b) > 0 ? (i * a + (i + 1) * b) / (a + b) : i;
            }
        }

        private void parameters(int target) {
            GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
            GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
            // Bords étirés : le flou reste plein au bord, sans halo sombre.
            GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
            GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
        }

        private void updateMask(double seconds) {
            BrowtherIntroMedia.Veil veil = mVeil;
            int index = mTrack.indexAt(seconds);
            if (index == mMaskIndex && veil.equals(mMaskVeil)) return;
            mMaskIndex = index;
            mMaskVeil = veil;
            List<BrowtherIntroMedia.Person> persons =
                    index < 0 ? java.util.Collections.emptyList() : mTrack.mFrames.get(index);
            float feather = 10f * mSmallWidth / BrowtherIntroMedia.VIDEO_WIDTH;
            BrowtherIntroMedia.drawMask(mMaskBitmap, persons, veil, feather, mMaskPaint, mMaskPath);
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, mMaskTexture);
            GLUtils.texSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, mMaskBitmap);
        }

        private void draw() {
            // 1. Réduction au quart.
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, mFbos[0]);
            GLES20.glViewport(0, 0, mSmallWidth, mSmallHeight);
            GLES20.glUseProgram(mDownsampleProgram);
            bindQuad(mDownsampleProgram, mTexMatrix);
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
            GLES20.glBindTexture(GL_TEXTURE_EXTERNAL_OES, mVideoTexture);
            GLES20.glUniform1i(GLES20.glGetUniformLocation(mDownsampleProgram, "uVideo"), 0);
            GLES20.glUniform2f(
                    GLES20.glGetUniformLocation(mDownsampleProgram, "uStep"),
                    1f / BrowtherIntroMedia.VIDEO_WIDTH,
                    1f / 506f);
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);

            // 2. Flou horizontal puis vertical.
            blurPass(mFboTextures[0], mFbos[1], 1f / mSmallWidth, 0f);
            blurPass(mFboTextures[1], mFbos[0], 0f, 1f / mSmallHeight);

            // 3. Composition sur la vignette.
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0);
            GLES20.glViewport(0, 0, mWidth, mHeight);
            GLES20.glUseProgram(mCompositeProgram);
            bindQuad(mCompositeProgram, mTexMatrix);
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
            GLES20.glBindTexture(GL_TEXTURE_EXTERNAL_OES, mVideoTexture);
            GLES20.glUniform1i(GLES20.glGetUniformLocation(mCompositeProgram, "uVideo"), 0);
            GLES20.glActiveTexture(GLES20.GL_TEXTURE1);
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, mFboTextures[0]);
            GLES20.glUniform1i(GLES20.glGetUniformLocation(mCompositeProgram, "uBlurred"), 1);
            GLES20.glActiveTexture(GLES20.GL_TEXTURE2);
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, mMaskTexture);
            GLES20.glUniform1i(GLES20.glGetUniformLocation(mCompositeProgram, "uMask"), 2);
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
            EGL14.eglSwapBuffers(mDisplay, mEglSurface);
        }

        private void blurPass(int sourceTexture, int targetFbo, float dx, float dy) {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, targetFbo);
            GLES20.glViewport(0, 0, mSmallWidth, mSmallHeight);
            GLES20.glUseProgram(mBlurProgram);
            bindQuad(mBlurProgram, mIdentity);
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, sourceTexture);
            GLES20.glUniform1i(GLES20.glGetUniformLocation(mBlurProgram, "uTexture"), 0);
            GLES20.glUniform2f(GLES20.glGetUniformLocation(mBlurProgram, "uDirection"), dx, dy);
            GLES20.glUniform1fv(
                    GLES20.glGetUniformLocation(mBlurProgram, "uWeights"), TAPS, mWeights, 0);
            GLES20.glUniform1fv(
                    GLES20.glGetUniformLocation(mBlurProgram, "uOffsets"), TAPS, mOffsets, 0);
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
        }

        private void bindQuad(int program, float[] texMatrix) {
            int position = GLES20.glGetAttribLocation(program, "aPosition");
            int texCoord = GLES20.glGetAttribLocation(program, "aTexCoord");
            mQuad.position(0);
            GLES20.glEnableVertexAttribArray(position);
            GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 16, mQuad);
            mQuad.position(2);
            GLES20.glEnableVertexAttribArray(texCoord);
            GLES20.glVertexAttribPointer(texCoord, 2, GLES20.GL_FLOAT, false, 16, mQuad);
            mQuad.position(0);
            GLES20.glUniformMatrix4fv(
                    GLES20.glGetUniformLocation(program, "uTexMatrix"), 1, false, texMatrix, 0);
        }

        private int program(String vertexSource, String fragmentSource) {
            int vertex = shader(GLES20.GL_VERTEX_SHADER, vertexSource);
            int fragment = shader(GLES20.GL_FRAGMENT_SHADER, fragmentSource);
            int program = GLES20.glCreateProgram();
            GLES20.glAttachShader(program, vertex);
            GLES20.glAttachShader(program, fragment);
            GLES20.glLinkProgram(program);
            int[] status = new int[1];
            GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0);
            if (status[0] != GLES20.GL_TRUE) {
                String log = GLES20.glGetProgramInfoLog(program);
                GLES20.glDeleteProgram(program);
                throw new RuntimeException("link : " + log);
            }
            return program;
        }

        private int shader(int type, String source) {
            int shader = GLES20.glCreateShader(type);
            GLES20.glShaderSource(shader, source);
            GLES20.glCompileShader(shader);
            int[] status = new int[1];
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0);
            if (status[0] != GLES20.GL_TRUE) {
                String log = GLES20.glGetShaderInfoLog(shader);
                GLES20.glDeleteShader(shader);
                throw new RuntimeException("shader : " + log);
            }
            return shader;
        }

        private void teardownGl() {
            if (mVideoSurface != null) mVideoSurface.release();
            if (mVideoSurfaceTexture != null) mVideoSurfaceTexture.release();
            mVideoSurface = null;
            mVideoSurfaceTexture = null;
            if (mDisplay != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(
                        mDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT);
                if (mEglSurface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglDestroySurface(mDisplay, mEglSurface);
                }
                if (mEglContext != EGL14.EGL_NO_CONTEXT) {
                    EGL14.eglDestroyContext(mDisplay, mEglContext);
                }
                EGL14.eglTerminate(mDisplay);
            }
            mDisplay = EGL14.EGL_NO_DISPLAY;
            mEglSurface = EGL14.EGL_NO_SURFACE;
            mEglContext = EGL14.EGL_NO_CONTEXT;
            if (mMaskBitmap != null) mMaskBitmap.recycle();
            mMaskBitmap = null;
        }
    }

    /**
     * Décodage de la vidéo dans la texture, au rythme de ses horodatages, en boucle.
     *
     * <p>MediaCodec plutôt que MediaPlayer : l'horodatage d'une image rendue par MediaCodec est
     * celui <b>du média</b>, alors que MediaPlayer donne l'heure de l'horloge système. C'est lui qui
     * choisit le contour du voile.
     */
    private static final class Decoder extends Thread {
        private final Context mContext;
        private final Surface mSurface;
        private final Object mLock = new Object();
        private volatile boolean mRunning = true;
        private boolean mPaused;
        /** Premier horodatage du flux (µs) : le JSON compte depuis 0. */
        private volatile long mFirstPtsUs = -1;

        Decoder(Context context, Surface surface) {
            super("BrowtherIntroVideoDecoder");
            mContext = context;
            mSurface = surface;
        }

        double mediaSeconds(long surfaceTimestampNs) {
            long first = mFirstPtsUs;
            if (first < 0) return 0;
            return Math.max(0, surfaceTimestampNs / 1000L - first) / 1_000_000d;
        }

        void setPaused(boolean paused) {
            synchronized (mLock) {
                mPaused = paused;
                mLock.notifyAll();
            }
        }

        void shutdown() {
            mRunning = false;
            setPaused(false);
            try {
                join(1000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }

        @Override
        public void run() {
            MediaExtractor extractor = new MediaExtractor();
            MediaCodec codec = null;
            try (AssetFileDescriptor fd = BrowtherIntroUi.openFd(mContext, BrowtherIntroMedia.VIDEO)) {
                extractor.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength());
                MediaFormat format = null;
                for (int i = 0; i < extractor.getTrackCount(); i++) {
                    MediaFormat candidate = extractor.getTrackFormat(i);
                    String mime = candidate.getString(MediaFormat.KEY_MIME);
                    if (mime != null && mime.startsWith("video/")) {
                        extractor.selectTrack(i);
                        format = candidate;
                        break;
                    }
                }
                if (format == null) throw new IOException("aucune piste vidéo");
                codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));
                codec.configure(format, mSurface, null, 0);
                codec.start();
                loop(extractor, codec);
            } catch (IOException | RuntimeException e) {
                Log.e(TAG, "Voile vidéo : décodage impossible", e);
            } finally {
                if (codec != null) {
                    try {
                        codec.stop();
                    } catch (RuntimeException e) {
                        // Déjà arrêté.
                    }
                    codec.release();
                }
                extractor.release();
            }
        }

        private void loop(MediaExtractor extractor, MediaCodec codec) {
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false;
            long loopStartMs = -1;
            long loopFirstPtsUs = -1;
            while (mRunning) {
                synchronized (mLock) {
                    while (mPaused && mRunning) {
                        long pausedAt = SystemClock.uptimeMillis();
                        try {
                            mLock.wait();
                        } catch (InterruptedException e) {
                            return;
                        }
                        // La lecture reprend là où elle s'était arrêtée.
                        if (loopStartMs >= 0) loopStartMs += SystemClock.uptimeMillis() - pausedAt;
                    }
                }
                if (!inputDone) {
                    int input = codec.dequeueInputBuffer(10_000);
                    if (input >= 0) {
                        ByteBuffer buffer = codec.getInputBuffer(input);
                        int size = buffer == null ? -1 : extractor.readSampleData(buffer, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(
                                    input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(input, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int output = codec.dequeueOutputBuffer(info, 10_000);
                if (output < 0) continue;
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    codec.releaseOutputBuffer(output, false);
                    // Boucle : on repart du début.
                    extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC);
                    codec.flush();
                    inputDone = false;
                    loopStartMs = -1;
                    continue;
                }
                if (mFirstPtsUs < 0) mFirstPtsUs = info.presentationTimeUs;
                if (loopStartMs < 0) {
                    loopStartMs = SystemClock.uptimeMillis();
                    loopFirstPtsUs = info.presentationTimeUs;
                }
                long dueMs = loopStartMs + (info.presentationTimeUs - loopFirstPtsUs) / 1000;
                long waitMs;
                while (mRunning && (waitMs = dueMs - SystemClock.uptimeMillis()) > 0) {
                    try {
                        Thread.sleep(Math.min(waitMs, 50));
                    } catch (InterruptedException e) {
                        return;
                    }
                }
                if (!mRunning) return;
                codec.releaseOutputBuffer(output, true);
            }
        }
    }
}
