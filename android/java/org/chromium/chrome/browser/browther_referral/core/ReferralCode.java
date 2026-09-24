// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Le code de parrainage — `docs/PARRAINAGE.md` § 7.2 et § 12.6, pendant de
 * `darsunaa/packages/core/src/referral/code.ts` (`readReferralCodeInput`, « à reprendre tel
 * quel »).
 *
 * <p>Le code **dicté** fait 6 signes de l'alphabet du service (`referral/src/domain/codes.ts`), qui
 * n'a ni `s`, ni `0`/`o`, ni `1`/`l`/`i`, ni `b`/`8`, `u`/`v`, `z`/`2`. Le lien porte le
 * produit en clair : `go.devndin.com/browther-pfxd3r`.
 *
 * <p>🔴 **Toute évolution de la forme du code (préfixe, longueur, alphabet) doit passer ICI dans le
 * même chantier** : sinon un code tapé juste est refusé « avant le service », sans aucune erreur
 * côté serveur.
 */
public final class ReferralCode {
    private ReferralCode() {}

    static final String alphabet = "acdefghjkmnpqrtwxy34679";
    static final int length = 6;
    static final String productPrefix = ReferralProduct.key + "-";

    public enum InputError {
        EMPTY,
        /** « Un code de parrainage fait 6 caractères. » */
        LENGTH,
        /** Un signe qu'aucun code n'utilise (O, 0, I, 1…). */
        ALPHABET
    }

    /** Le `Result<String, InputError>` de Swift : le code, OU l'erreur. */
    public static final class Input {
        /** Le code à envoyer à `redeem` (majuscules), {@code null} en cas d'erreur. */
        public final String code;
        /** {@code null} quand la saisie est un code. */
        public final InputError error;

        private Input(String code, InputError error) {
            this.code = code;
            this.error = error;
        }

        public boolean isSuccess() {
            return code != null;
        }
    }

    private static Input success(String code) {
        return new Input(code.toUpperCase(Locale.ROOT), null);
    }

    private static Input failure(InputError error) {
        return new Input(null, error);
    }

    /**
     * Ce que quelqu'un a TAPÉ ou COLLÉ dans le champ du code d'un proche → le code à envoyer à
     * `redeem`, ou pourquoi ce n'en est pas un.
     *
     * <p>⭐ **On sait ce qu'on attend** : une saisie impossible se dit TOUT DE SUITE, dans ses propres
     * mots (« un code fait 6 caractères »), ⛔ sans aller demander au service — qui ne saurait
     * répondre que « ce code ne correspond à personne » (recette du 2026-09-10).
     *
     * <p>⚠️ **Un LIEN collé est accepté en silence** : on en tire le code (`?ref=`, `utm_source`, ou
     * le lien court), ⛔ mais l'interface ne l'annonce pas : le champ demande un code. Les espaces et
     * tirets d'un code recopié à la main sont retirés.
     */
    public static Input readInput(String raw) {
        String text = trim(raw == null ? "" : raw);
        if (text.isEmpty()) return failure(InputError.EMPTY);
        String linked = fromLink(text);
        if (linked != null) return success(linked);

        String bare = text.toLowerCase(Locale.ROOT);
        if (bare.startsWith(productPrefix)) bare = bare.substring(productPrefix.length());
        StringBuilder kept = new StringBuilder();
        for (int i = 0; i < bare.length(); i++) {
            char c = bare.charAt(i);
            if (c == ' ' || c == '.' || c == '_' || c == '-' || c == '\n' || c == '\r'
                    || c == '\u0085' || c == ' ' || c == ' ' || c == '\u000B'
                    || c == '\u000C') {
                continue;
            }
            kept.append(c);
        }
        bare = kept.toString();
        if (bare.codePointCount(0, bare.length()) != length) return failure(InputError.LENGTH);
        if (!isBare(bare)) return failure(InputError.ALPHABET);
        return success(bare);
    }

    /** Un code nu et EXACT (6 signes de l'alphabet), en minuscules ou majuscules. */
    public static boolean isBare(String value) {
        String lower = value.toLowerCase(Locale.ROOT);
        if (lower.length() != length) return false;
        for (int i = 0; i < lower.length(); i++) {
            if (alphabet.indexOf(lower.charAt(i)) < 0) return false;
        }
        return true;
    }

    /**
     * Le code porté par un lien, ou {@code null}. ⚠️ Un segment de chemin n'est pris que s'il porte
     * le préfixe du produit, ou s'il EST tout le chemin (`/pfxd3r`, `/l/pfxd3r`) : sinon la fin
     * d'une adresse quelconque de six signes passerait pour un code.
     */
    static String fromLink(String text) {
        if (!(text.contains("/") || text.contains("?") || text.contains("="))) return null;
        String candidate = text.contains("://") ? text : "https://" + text;
        // Comme `URLComponents(string:)` : une adresse avec des blancs n'est pas une adresse.
        for (int i = 0; i < candidate.length(); i++) {
            if (Character.isWhitespace(candidate.charAt(i))) return null;
        }
        int schemeEnd = candidate.indexOf("://");
        String rest = candidate.substring(schemeEnd + 3);
        int fragment = rest.indexOf('#');
        if (fragment >= 0) rest = rest.substring(0, fragment);
        int queryStart = rest.indexOf('?');
        String query = queryStart >= 0 ? rest.substring(queryStart + 1) : null;
        String beforeQuery = queryStart >= 0 ? rest.substring(0, queryStart) : rest;
        int pathStart = beforeQuery.indexOf('/');
        String path = pathStart >= 0 ? beforeQuery.substring(pathStart) : "";

        if (query != null) {
            for (String name : new String[] {"ref", "utm_source"}) {
                String value = queryValue(query, name);
                if (value == null) continue;
                String bare = trim(value).toLowerCase(Locale.ROOT);
                if (bare.startsWith(productPrefix)) bare = bare.substring(productPrefix.length());
                if (isBare(bare)) return bare;
            }
        }

        List<String> segments = new ArrayList<>();
        for (String segment : path.split("/")) {
            if (!segment.isEmpty()) segments.add(percentDecode(segment));
        }
        if (segments.isEmpty()) return null;
        String last = segments.get(segments.size() - 1).toLowerCase(Locale.ROOT);
        boolean prefixed = last.startsWith(productPrefix);
        String bare = prefixed ? last.substring(productPrefix.length()) : last;
        boolean wholePath =
                segments.size() == 1 || (segments.size() == 2 && segments.get(0).equals("l"));
        return (prefixed || wholePath) && isBare(bare) ? bare : null;
    }

    /**
     * Retire les blancs et retours à la ligne des deux bouts (`.whitespacesAndNewlines` de Swift,
     * espace insécable comprise). ⚠️ Pas `String.strip()` : il n'existe qu'à partir d'Android 13.
     */
    static String trim(String value) {
        int start = 0;
        int end = value.length();
        while (start < end && isBlank(value.charAt(start))) start++;
        while (end > start && isBlank(value.charAt(end - 1))) end--;
        return value.substring(start, end);
    }

    private static boolean isBlank(char c) {
        return Character.isWhitespace(c) || Character.isSpaceChar(c) || c == '\u0085';
    }

    /** La PREMIÈRE valeur du paramètre (`queryItems.first(where:)`), décodée. */
    private static String queryValue(String query, String name) {
        for (String pair : query.split("&")) {
            int eq = pair.indexOf('=');
            String key = percentDecode(eq >= 0 ? pair.substring(0, eq) : pair);
            if (!key.equals(name)) continue;
            // Un paramètre sans « = » a une valeur nulle : on passe au suivant, comme Swift.
            if (eq < 0) continue;
            return percentDecode(pair.substring(eq + 1));
        }
        return null;
    }

    /** Décode les `%XX` (UTF-8). ⚠️ Pas `URLDecoder` : il lit « + » comme une espace. */
    private static String percentDecode(String value) {
        if (value.indexOf('%') < 0) return value;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        for (int i = 0; i < bytes.length; i++) {
            if (bytes[i] == '%' && i + 2 < bytes.length) {
                int hi = Character.digit(bytes[i + 1], 16);
                int lo = Character.digit(bytes[i + 2], 16);
                if (hi >= 0 && lo >= 0) {
                    out.write(hi * 16 + lo);
                    i += 2;
                    continue;
                }
            }
            out.write(bytes[i]);
        }
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }
}
