// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * Le transfert de la **vidéo du statut WhatsApp** — pendant de `ReferralStatusVideoLoader` (iOS,
 * `ReferralStatusVideoStore.swift`) ; règle et pourquoi : {@link ReferralStatusVideo},
 * `private/docs/PARRAINAGE.md` § 11.
 *
 * <p>Le manifeste d'abord (quelques centaines d'octets, borné à {@link #MANIFEST_TIMEOUT_MS}, ⛔
 * sans cache), puis la vidéo de la langue demandée si elle n'est pas déjà là. Une fois en cache,
 * plus aucun transfert : seul le manifeste est relu, pour suivre un changement ou une coupure.
 *
 * <p>🔴 **Ne lève jamais** : {@code null} = pas de vidéo, et le statut part avec l'image seule.
 *
 * <p>⚠️ **SYNCHRONE** : ⛔ jamais sur le fil de l'UI — l'appelant ({@code
 * ReferralStatusVideoStore}) le pose sur un fil d'arrière-plan. Ici et pas à côté du magasin : le
 * cœur ne dépend que de {@code java.*}, donc la taille exacte, le fichier partiel et le ménage se
 * vérifient sur la JVM du Mac (`private/scripts/android-referral-tests/`), avec une {@link Source}
 * factice — sur Android, rien de tout ça ne se voit avant un vrai appareil.
 */
public final class ReferralStatusVideoLoader {
    private ReferralStatusVideoLoader() {}

    /** D'où viennent les octets : le réseau dans l'app, une fausse source dans les tests. */
    public interface Source {
        /**
         * Le corps d'une réponse 200 (à fermer par l'appelant). Tout le reste — autre statut, hôte
         * injoignable, silence de plus de {@code timeoutMs} — lève.
         */
        InputStream open(String url, int timeoutMs) throws IOException;
    }

    /** Le manifeste ne retient jamais la feuille : au-delà, c'est « pas de vidéo » pour cette fois. */
    public static final int MANIFEST_TIMEOUT_MS = 4_000;

    /** La vidéo (~5 Mo) : bornée par le SILENCE (30 s sans un octet), pas par sa durée totale. */
    static final int VIDEO_TIMEOUT_MS = 30_000;

    /** Un manifeste fait quelques centaines d'octets : au-delà, ce n'en est pas un. */
    private static final int MANIFEST_MAX_BYTES = 64 * 1024;

    /** Le suffixe d'un transfert en cours : le nom de la vidéo ne désigne jamais un fichier partiel. */
    private static final String PARTIAL = ".part";

    public static final Source NETWORK = ReferralStatusVideoLoader::openNetwork;

    /**
     * Le fichier local de la vidéo de {@code language} (celle de l'IMAGE du statut — ⛔ jamais un
     * repli ici), dans {@code folder}, ou {@code null} s'il n'y en a pas.
     */
    public static File load(File folder, String language) {
        return load(folder, language, ReferralStatusVideo.MANIFEST_URL, NETWORK);
    }

    static File load(File folder, String language, String manifestUrl, Source source) {
        try {
            ReferralStatusVideo.Entry entry =
                    ReferralStatusVideo.pick(
                            ReferralStatusVideo.manifest(readManifest(manifestUrl, source)), language);
            if (entry == null) return null;
            if (!folder.isDirectory() && !folder.mkdirs()) return null;
            File file = new File(folder, ReferralStatusVideo.fileName(entry));

            if (!ReferralStatusVideo.isComplete(entry, size(file))) {
                delete(file);
                File partial = new File(folder, file.getName() + PARTIAL);
                boolean whole = download(entry, partial, source) && partial.renameTo(file);
                // ⚠️ Un transfert interrompu laisse un fichier court : seule la taille exacte du
                // manifeste fait foi.
                if (!whole || !ReferralStatusVideo.isComplete(entry, size(file))) {
                    delete(partial);
                    delete(file);
                    return null;
                }
            }

            // Les vidéos d'avant (autre version, autre langue, transfert abandonné) ne serviront
            // plus. Ménage seulement : un fichier qui résiste ne gêne personne.
            File[] others = folder.listFiles();
            if (others != null) {
                for (File other : others) {
                    if (!other.getName().equals(file.getName())) delete(other);
                }
            }
            return file;
        } catch (IOException | RuntimeException e) {
            return null;
        }
    }

    /** Le texte du manifeste, ou {@code null} s'il est trop gros pour en être un. */
    private static String readManifest(String url, Source source) throws IOException {
        long deadline = System.nanoTime() + MANIFEST_TIMEOUT_MS * 1_000_000L;
        try (InputStream in = source.open(url, MANIFEST_TIMEOUT_MS)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int n;
            while ((n = in.read(buffer)) != -1) {
                out.write(buffer, 0, n);
                if (out.size() > MANIFEST_MAX_BYTES) return null;
                // Le délai borne chaque attente ; ceci borne aussi un goutte-à-goutte.
                if (System.nanoTime() > deadline) throw new IOException("manifeste trop lent");
            }
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    /**
     * Écrit la vidéo dans {@code target}. {@code false} dès qu'elle dépasse la taille annoncée : on
     * ne télécharge jamais plus que ce que le manifeste a dit (au plus 16 Mo).
     */
    private static boolean download(ReferralStatusVideo.Entry entry, File target, Source source)
            throws IOException {
        long written = 0;
        try (InputStream in = source.open(entry.url, VIDEO_TIMEOUT_MS);
                OutputStream out = new FileOutputStream(target)) {
            byte[] buffer = new byte[64 * 1024];
            int n;
            while ((n = in.read(buffer)) != -1) {
                written += n;
                if (written > entry.bytes) return false;
                out.write(buffer, 0, n);
            }
        }
        return written == entry.bytes;
    }

    private static Long size(File file) {
        return file.isFile() ? Long.valueOf(file.length()) : null;
    }

    /** Au mieux : un fichier qui résiste sera effacé au prochain passage. */
    private static void delete(File file) {
        file.delete();
    }

    /**
     * ⚠️ `URL#openConnection` direct, voulu : le cœur ne dépend que de `java.*` (tests JVM, § 8.6).
     * Chromium le signale (`UseNetworkAnnotations`) — l'exception est levée sur la méthode, avec
     * cette raison, comme dans {@link ReferralClient}. ⛔ Pas de cache HTTP, pas de cookies.
     */
    @SuppressWarnings("UseNetworkAnnotations")
    private static InputStream openNetwork(String url, int timeoutMs) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        try {
            connection.setConnectTimeout(timeoutMs);
            connection.setReadTimeout(timeoutMs);
            connection.setUseCaches(false);
            connection.setRequestProperty("Cache-Control", "no-cache");
            int code = connection.getResponseCode();
            if (code != 200) throw new IOException("statut " + code);
            return new FilterInputStream(connection.getInputStream()) {
                @Override
                public void close() throws IOException {
                    try {
                        super.close();
                    } finally {
                        connection.disconnect();
                    }
                }
            };
        } catch (IOException | RuntimeException e) {
            connection.disconnect();
            throw e;
        }
    }
}
