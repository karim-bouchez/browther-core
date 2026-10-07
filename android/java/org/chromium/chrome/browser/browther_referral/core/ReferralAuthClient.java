// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Les appels au COMPTE — `auth.devndin.com` (Better Auth) et la porte du paiement de
 * `browther-api`. Port de `ReferralAuthClient` (`ReferralAccount.swift`, iOS : la référence, finie
 * et vérifiée), même transport que {@link ReferralClient}.
 *
 * <p>⛔ **Pas de cookies, pas de cache** : le jeton se présente en `Authorization: Bearer` (plugin
 * `bearer` de l'auth-service), comme le font l'iPhone et le desktop. Chaque appel dit quelle app
 * parle (`X-App-Id: browther` : habillage des courriels) et dans quelle langue (`Accept-Language`).
 *
 * <p>⚠️ **SYNCHRONE**, comme {@link ReferralClient} : chaque appel bloque jusqu'à la réponse — ⛔
 * jamais sur le fil de l'UI. ⛔ Le jeton, le code et l'adresse ne vont dans AUCUN message
 * d'exception ni aucun journal.
 *
 * <p>⚠️ Pas `final`, au contraire du Swift : l'aperçu à l'émulateur
 * (`private/scripts/android-intro-preview/`) en dérive un faux, sans réseau, que le contrôleur
 * reçoit par sa `Platform`. ⛔ Rien d'autre ne doit en hériter.
 */
public class ReferralAuthClient {
    /** L'hôte de l'auth-service — le SEUL d'où un retour de connexion est écouté sur Android. */
    public static final String authHost = "auth.devndin.com";

    public static final String authURL = "https://" + authHost;
    public static final String apiURL = "https://browther-api.devndin.com";

    /** Le schéma du retour — l'entrée `browther` de `SSO_APP_LINKS` côté auth-service. */
    public static final String callbackScheme = "browther";

    /** Où l'auth-service renvoie après Google / Apple, sans sa requête. */
    static final String callbackRoute = callbackScheme + "://auth/callback";

    /** L'app vue par l'auth-service : branding de ses pages et de ses e-mails. */
    static final String appId = "browther";

    /** Les appels au compte sont bornés (20 s, comme l'iOS) : aucun ne retient un écran sans fin. */
    static final int timeout = 20_000;

    public enum Provider {
        GOOGLE("google"),
        APPLE("apple");

        public final String rawValue;

        Provider(String rawValue) {
            this.rawValue = rawValue;
        }
    }

    private final String authBase;
    private final String apiBase;
    private final String language;

    /**
     * @param language la langue de l'app (`fr`, `pt-BR`…) : celle des courriels que l'auth-service
     *     envoie.
     */
    public ReferralAuthClient(String language) {
        this(authURL, apiURL, language);
    }

    /** Les adresses en paramètre : les tests (serveur local) seulement. */
    public ReferralAuthClient(String authBase, String apiBase, String language) {
        this.authBase = trimSlash(authBase);
        this.apiBase = trimSlash(apiBase);
        this.language = language == null || language.isEmpty() ? "en" : language;
    }

    private static String trimSlash(String base) {
        return base.endsWith("/") ? base.substring(0, base.length() - 1) : base;
    }

    // MARK: - Google / Apple (la page de l'auth-service, puis le retour)

    /**
     * La page où commence la connexion Google / Apple — elle finit sur
     * `browther://auth/callback?code=…`.
     */
    public static String signInUrl(Provider provider) {
        return authURL + "/sso/initiate/" + provider.rawValue + "?app=" + appId;
    }

    /**
     * Cette adresse est-elle le retour de la connexion (`browther://auth/callback`, avec ou sans
     * code) ? ⚠️ Sur Android elle est rattrapée DANS le chemin de navigation du navigateur : la
     * route entière est exigée, ⛔ pas le schéma seul — `browther://autre-chose` n'est pas à nous.
     */
    public static boolean isCallback(String url) {
        if (url == null || !url.regionMatches(true, 0, callbackRoute, 0, callbackRoute.length())) {
            return false;
        }
        if (url.length() == callbackRoute.length()) return true;
        char next = url.charAt(callbackRoute.length());
        return next == '?' || next == '#' || next == '/';
    }

    /** Le code à usage unique du retour, lu dans `browther://auth/callback?code=…`. */
    public static String callbackCode(String url) {
        if (!isCallback(url)) return null;
        int question = url.indexOf('?');
        if (question < 0) return null;
        int hash = url.indexOf('#');
        // Un « ? » après le « # » appartient au fragment, pas à la requête.
        if (hash >= 0 && hash < question) return null;
        String query = url.substring(question + 1, hash < 0 ? url.length() : hash);
        for (String pair : query.split("&")) {
            int equals = pair.indexOf('=');
            if (equals < 0 || !"code".equals(pair.substring(0, equals))) continue;
            String raw = pair.substring(equals + 1);
            String value = percentDecode(raw);
            if (value == null) value = raw;
            return value.isEmpty() ? null : value;
        }
        return null;
    }

    /**
     * Échange le code à usage unique (5 min, une fois) contre le jeton de session. L'auth-service
     * rend l'en-tête `Cookie` de la connexion : le jeton est la valeur du cookie `*.session_token`
     * (signée — le plugin `bearer` l'accepte telle quelle).
     */
    public String exchange(String code) throws ReferralAuthFailure {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("code", code);
        Sent sent = send("POST", authBase, "/api/auth/sso/exchange-code", body, null);
        String cookie = sent.status == 200 ? ReferralAuthReply.string(sent.reply().object(), "cookie") : null;
        String token = cookie == null ? null : sessionToken(cookie);
        if (token == null) throw new ReferralAuthFailure(ReferralAuthFailure.Kind.FAILED);
        return token;
    }

    /** Le jeton dans un en-tête `Cookie` (`a=1; __Secure-x.session_token=…`), ou {@code null}. */
    static String sessionToken(String cookieHeader) {
        for (String pair : cookieHeader.split(";")) {
            int equals = pair.indexOf('=');
            if (equals < 0) continue;
            String name = pair.substring(0, equals).trim();
            String value = pair.substring(equals + 1).trim();
            // ⚠️ Le NOM porte un préfixe par environnement (`COOKIE_PREFIX`) et `__Secure-` : seul
            // le suffixe est stable.
            if (!name.endsWith(".session_token") || value.isEmpty()) continue;
            String decoded = percentDecode(value);
            return decoded == null ? value : decoded;
        }
        return null;
    }

    /**
     * Défait les `%XX` (UTF-8). ⚠️ Pas `URLDecoder` : il changerait un « + » en espace, et la
     * signature du jeton en contient. {@code null} si l'encodage est invalide — l'appelant garde
     * alors la valeur brute, comme `removingPercentEncoding ?? valeur` côté Swift.
     */
    static String percentDecode(String value) {
        if (value.indexOf('%') < 0) return value;
        ByteArrayOutputStream out = new ByteArrayOutputStream(value.length());
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        for (int i = 0; i < bytes.length; i++) {
            if (bytes[i] != '%') {
                out.write(bytes[i]);
                continue;
            }
            if (i + 2 >= bytes.length) return null;
            int high = Character.digit((char) bytes[i + 1], 16);
            int low = Character.digit((char) bytes[i + 2], 16);
            if (high < 0 || low < 0) return null;
            out.write(high * 16 + low);
            i += 2;
        }
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }

    // MARK: - Le code par e-mail (sans quitter l'app)

    /** Envoie un code à 6 chiffres par e-mail (courriel habillé Browther, dans la langue de l'app). */
    public void sendEmailCode(String email) throws ReferralAuthFailure {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("email", email);
        body.put("type", "sign-in");
        Sent sent = send("POST", authBase, "/api/auth/email-otp/send-verification-otp", body, null);
        if (!sent.ok()) throw new ReferralAuthFailure(ReferralAuthFailure.Kind.FAILED);
    }

    /** Le code saisi → le jeton de session. */
    public String verifyEmailCode(String email, String code) throws ReferralAuthFailure {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("email", email);
        body.put("otp", code);
        Sent sent = send("POST", authBase, "/api/auth/sign-in/email-otp", body, null);
        if (!sent.ok()) {
            throw new ReferralAuthFailure(
                    sent.status >= 400 && sent.status < 500
                            ? ReferralAuthFailure.Kind.BAD_CODE
                            : ReferralAuthFailure.Kind.FAILED);
        }
        // `set-auth-token` (plugin `bearer`) : le jeton signé. Sinon, le `token` du corps — brut,
        // que le plugin signe lui-même.
        if (sent.authToken != null && !sent.authToken.isEmpty()) return sent.authToken;
        String token = ReferralAuthReply.string(sent.reply().object(), "token");
        if (token != null && !token.isEmpty()) return token;
        throw new ReferralAuthFailure(ReferralAuthFailure.Kind.FAILED);
    }

    // MARK: - Vivre avec la session

    /** Qui est-ce ? L'identifiant du compte devient le sujet du parrainage. */
    public ReferralAccount account(String token) throws ReferralAuthFailure {
        Sent sent = send("GET", authBase, "/api/auth/get-session", null, token);
        Map<String, Object> object = sent.status == 200 ? sent.reply().object() : null;
        Object user = object == null ? null : object.get("user");
        if (user instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> fields = (Map<String, Object>) user;
            String id = ReferralAuthReply.string(fields, "id");
            if (id != null && !id.isEmpty()) {
                return new ReferralAccount(
                        id,
                        ReferralAuthReply.string(fields, "email"),
                        ReferralAuthReply.string(fields, "name"));
            }
        }
        // ⚠️ Better Auth répond `200` + `null` pour « pas de session » : ce n'est pas un compte.
        throw new ReferralAuthFailure(ReferralAuthFailure.Kind.FAILED);
    }

    /** Révoque la session côté serveur — ⛔ sans jamais bloquer la déconnexion. */
    public void signOut(String token) {
        quietly("POST", authBase, "/api/auth/sign-out", new LinkedHashMap<String, Object>(), token);
    }

    // MARK: - Se déclarer, et supprimer le compte (§ 7.1, `docs/AUTH.md`)

    /**
     * Dire à l'auth-service que ce compte sert à Browther (`app_registrations`).
     *
     * <p>🔴 **À faire dès la connexion, ATTENDU, avant le rattachement** : c'est ce qui prouve,
     * plus tard, qu'un compte est NÉ ici — et donc qu'il peut être supprimé d'ici. Un compte bien
     * plus vieux que sa première déclaration venait d'une autre app dev&din, qui y garde peut-être
     * des données : sa suppression est refusée (`auth-service/src/lib/account-deletion.ts`).
     * Silencieux : un échec rend seulement le compte non supprimable d'ici, jamais l'inverse.
     */
    public void registerApp(String token) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("appName", appId);
        quietly("POST", authBase, "/api/auth/register-app", body, token);
    }

    /** Ce compte peut-il être supprimé d'ici ? ⭐ Se demande AVANT d'envoyer le code. */
    public ReferralDeletability deletable(String token) {
        return ReferralDeletability.fromReply(
                quietly("GET", authBase, "/api/auth/account/deletable", null, token));
    }

    /**
     * Le code de confirmation à six chiffres, envoyé à l'adresse du compte (courriel habillé
     * Browther, dans la langue de l'app).
     */
    public ReferralDeletionCode sendDeletionCode(String token) {
        return ReferralDeletionCode.fromReply(
                quietly(
                        "POST",
                        authBase,
                        "/api/auth/send-deletion-otp",
                        new LinkedHashMap<String, Object>(),
                        token));
    }

    /**
     * Supprime le compte dev&din ET ce qu'il portait, d'UN seul appel : l'auth-service fait d'abord
     * effacer le parrainage au service de parrainage (`/v1/account/forget`) — ⛔ ce client ne
     * l'appelle pas lui-même — et ne supprime rien si celui-ci ne répond pas. ⛔ Ne touche à rien de
     * LOCAL : c'est au contrôleur de ramener le sujet à l'appareil, et seulement sur
     * {@link ReferralDeletionOutcome.Kind#DELETED}.
     */
    public ReferralDeletionOutcome deleteAccount(String token, String otp) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("otp", otp);
        body.put("app", appId);
        return ReferralDeletionOutcome.fromReply(
                quietly("POST", authBase, "/api/auth/account/delete", body, token));
    }

    /**
     * ⭐ `POST /api/billing/link` : l'abonnement Polar payé sur l'ORDINATEUR (sans compte, ou avec
     * l'e-mail du compte) est rejoué sur le compte. La cible est le compte authentifié ; `fromRef`
     * ne sert qu'à retrouver le client Polar. {@code true} = quelque chose a été rattaché. ⛔
     * Jamais bloquant : toute panne vaut « rien à rattacher ».
     */
    public boolean linkBilling(String token, String fromRef) {
        Map<String, Object> body = new LinkedHashMap<>();
        if (fromRef != null) body.put("fromRef", fromRef);
        ReferralAuthReply reply = quietly("POST", apiBase, "/api/billing/link", body, token);
        return reply != null
                && reply.status == 200
                && Boolean.TRUE.equals(ReferralAuthReply.bool(reply.object(), "linked"));
    }

    // MARK: - Transport

    /** Une réponse reçue : le code, le corps, et l'en-tête `set-auth-token` s'il est là. */
    private static final class Sent {
        final int status;
        final String body;
        final String authToken;

        Sent(int status, String body, String authToken) {
            this.status = status;
            this.body = body;
            this.authToken = authToken;
        }

        boolean ok() {
            return status >= 200 && status < 300;
        }

        ReferralAuthReply reply() {
            return new ReferralAuthReply(status, body);
        }
    }

    /** Un appel au nom du compte, rendu tel quel aux règles. {@code null} = injoignable. */
    private ReferralAuthReply quietly(
            String method, String base, String path, Map<String, Object> body, String token) {
        try {
            return send(method, base, path, body, token).reply();
        } catch (ReferralAuthFailure e) {
            return null;
        }
    }

    @SuppressWarnings("UseNetworkAnnotations")
    private Sent send(
            String method, String base, String path, Map<String, Object> body, String token)
            throws ReferralAuthFailure {
        HttpURLConnection connection = null;
        try {
            // ⚠️ `URL#openConnection` direct, voulu : le cœur ne dépend que de `java.*` (tests JVM,
            // § 8.6) — même exception que `ReferralClient`, levée sur la méthode.
            connection = (HttpURLConnection) new URL(base + path).openConnection();
            connection.setConnectTimeout(timeout);
            connection.setReadTimeout(timeout);
            connection.setRequestMethod(method);
            connection.setUseCaches(false);
            // ⛔ Jamais de redirection suivie : le jeton ne part qu'à l'adresse qu'on a écrite.
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("X-App-Id", appId);
            connection.setRequestProperty("Accept-Language", language);
            if (token != null) connection.setRequestProperty("Authorization", "Bearer " + token);
            if (body != null) {
                byte[] payload = ReferralJson.stringify(body).getBytes(StandardCharsets.UTF_8);
                connection.setRequestProperty("Content-Type", "application/json");
                connection.setDoOutput(true);
                // ⚠️ Pas de `setFixedLengthStreamingMode` ici, au contraire de `ReferralClient` : en
                // mode « streaming », un `401` fait perdre le CORPS de la réponse sur la JVM — or
                // c'est lui qui distingue un code faux (`INVALID_CODE`) d'une session perdue.
                try (OutputStream out = connection.getOutputStream()) {
                    out.write(payload);
                }
            }
            int status = connection.getResponseCode();
            String text = "";
            // ⚠️ Hors 2xx le corps est dans le flux d'ERREUR — et il porte du sens (`401`, `409`).
            try (InputStream in =
                    status >= 400 ? connection.getErrorStream() : connection.getInputStream()) {
                if (in != null) text = readAll(in);
            } catch (IOException e) {
                // Un corps illisible n'efface pas le code HTTP : les règles trancheront sur lui.
            }
            return new Sent(status, text, connection.getHeaderField("set-auth-token"));
        } catch (IOException | RuntimeException e) {
            throw new ReferralAuthFailure(ReferralAuthFailure.Kind.UNREACHABLE);
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static String readAll(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int n;
        while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }

    /**
     * La langue de l'app telle que l'auth-service doit la recevoir : son code de LANGUE seul (`fr`,
     * `es`, `ar`…), sans région ni écriture — `en` quand on ne la connaît pas.
     *
     * <p>⚠️ Pas l'étiquette complète : l'auth-service choisit la langue de ses courriels en
     * cherchant « ar » puis « en » DANS l'en-tête (`detectLanguage`), et `es-AR` (l'espagnol
     * d'Argentine) partirait en arabe. L'iPhone envoie de même le code de sa traduction.
     */
    public static String languageTag(Locale locale) {
        if (locale == null) return "en";
        // `toLanguageTag` normalise les anciens codes de Java (`iw` → `he`, `in` → `id`).
        String tag = locale.toLanguageTag();
        int dash = tag.indexOf('-');
        String language = dash < 0 ? tag : tag.substring(0, dash);
        return language.isEmpty() || "und".equals(language) ? "en" : language;
    }
}
