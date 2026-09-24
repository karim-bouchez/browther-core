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
import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Le client du service — `referral/docs/API.md`. **Tout est en POST** : le sujet ne doit jamais se
 * promener dans une URL. Pas d'authentification : un secret dans une app n'est pas un secret (§
 * 10.3).
 *
 * <p>⚠️ **Toutes les lectures sont bornées** (8 s) : le parrainage ne doit jamais retenir un écran.
 * Une écriture ne l'est pas autant (30 s) — un renvoi créerait un doublon —, SAUF les écritures
 * idempotentes qui peignent l'écran (`register`, `transfer`).
 *
 * <p>⚠️ **SYNCHRONE** : chaque appel bloque jusqu'à la réponse — ⛔ jamais sur le fil de l'UI,
 * l'appelant le pose sur un fil d'arrière-plan. ⛔ Pas de cache HTTP ; pas de cookies (le client
 * n'en lit ni n'en pose).
 */
public final class ReferralClient {
    private final String baseURL;
    private final ReferralIdentityBody identity;

    static final int readTimeout = 8_000;
    static final int writeTimeout = 30_000;

    public ReferralClient(String baseURL, ReferralIdentityBody identity) {
        this.baseURL = baseURL.endsWith("/") ? baseURL.substring(0, baseURL.length() - 1) : baseURL;
        this.identity = identity;
    }

    public ReferralClient(ReferralIdentityBody identity) {
        this(ReferralProduct.serviceURL, identity);
    }

    public String subjectRef() {
        return identity.subjectRef;
    }

    /** À chaque ouverture : crée le sujet si besoin, rend le statut complet. */
    public ReferralStatus register() throws ReferralUnavailable {
        return status(call("/v1/register", Collections.<String, Object>emptyMap(), true, null));
    }

    public ReferralStatus status() throws ReferralUnavailable {
        return status(call("/v1/status", Collections.<String, Object>emptyMap(), true, null));
    }

    /** ⭐ Le mois démarre ICI (à l'annonce), ⛔ pas à l'installation (§ 4). */
    public ReferralStatus startTrial() throws ReferralUnavailable {
        return status(call("/v1/trial", Collections.<String, Object>emptyMap(), false, null));
    }

    /**
     * Un partage a ABOUTI (destinataire choisi, ou message copié). ⛔ Ne crée AUCUNE invitation (§
     * 12.1) : il ne sert qu'au moment « partage » des 3 jours.
     */
    public ShareOutcome share() throws ReferralUnavailable {
        ReferralJson.Obj o = call("/v1/share", Collections.<String, Object>emptyMap(), false, null);
        try {
            return ShareOutcome.fromJson(o);
        } catch (ReferralJson.JsonException e) {
            throw new ReferralUnavailable(null);
        }
    }

    public RedeemOutcome redeem(String code) throws ReferralUnavailable {
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("code", code);
        ReferralJson.Obj o = call("/v1/redeem", extra, false, null);
        try {
            return RedeemOutcome.fromJson(o);
        } catch (ReferralJson.JsonException e) {
            throw new ReferralUnavailable(null);
        }
    }

    /** Un fait d'usage du filleul — Browther : un `default_browser_day` par jour. */
    public ProgressOutcome reportProgress(String event, String eventKey, Instant occurredAt)
            throws ReferralUnavailable {
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("event", event);
        extra.put("eventKey", eventKey);
        extra.put("occurredAt", ReferralDate.string(occurredAt));
        ReferralJson.Obj o = call("/v1/progress", extra, false, null);
        try {
            return ProgressOutcome.fromJson(o);
        } catch (ReferralJson.JsonException e) {
            throw new ReferralUnavailable(null);
        }
    }

    /**
     * ⭐ L'appareil rejoint le compte (§ 7.1) — à appeler juste après la connexion. Idempotent côté
     * service ; borné, car il peint l'écran.
     */
    public TransferOutcome transfer(String fromRef, String toRef) throws ReferralUnavailable {
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("fromRef", fromRef);
        extra.put("toRef", toRef);
        ReferralJson.Obj o = call("/v1/transfer", extra, true, null);
        try {
            return TransferOutcome.fromJson(o);
        } catch (ReferralJson.JsonException e) {
            throw new ReferralUnavailable(null);
        }
    }

    /**
     * 🎁 La porte factice du paiement Android (`docs/PARRAINAGE.md` § 12.27) : la personne a choisi
     * de payer là où le paiement n'existe pas encore. Le service offre **1 mois, UNE fois par
     * sujet**, quelle que soit la formule — ⚠️ la formule n'est donc PAS envoyée (elle ne sert qu'à
     * l'analytique, `billing_gift {period, granted}`). Une écriture : pas de renvoi automatique.
     */
    public GiftOutcome gift() throws ReferralUnavailable {
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("reason", "billing_unavailable");
        ReferralJson.Obj o = call("/v1/gift", extra, false, null);
        try {
            return GiftOutcome.fromJson(o);
        } catch (ReferralJson.JsonException e) {
            throw new ReferralUnavailable(null);
        }
    }

    /** 🧪 Poser une situation COMPLÈTE (`POST /v1/admin/recette`, § 12.18). */
    public ReferralStatus applyRecette(String token, RecetteState state) throws ReferralUnavailable {
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("state", state.toJson());
        Map<String, String> headers = new LinkedHashMap<>();
        headers.put("X-Admin-Token", token);
        return status(call("/v1/admin/recette", extra, true, headers));
    }

    // MARK: - Transport

    private static ReferralStatus status(ReferralJson.Obj o) throws ReferralUnavailable {
        try {
            return ReferralStatus.fromJson(o);
        } catch (ReferralJson.JsonException e) {
            throw new ReferralUnavailable(null);
        }
    }

    /** Le corps commun de chaque appel (§ 7.1). */
    Map<String, Object> body(Map<String, Object> extra) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("product", identity.product);
        body.put("subjectRef", identity.subjectRef);
        body.put("platform", identity.platform.rawValue);
        if (identity.deviceRef != null) body.put("deviceRef", identity.deviceRef);
        body.putAll(extra);
        return body;
    }

    @SuppressWarnings("UseNetworkAnnotations")
    private ReferralJson.Obj call(
            String path, Map<String, Object> extra, boolean bounded, Map<String, String> headers)
            throws ReferralUnavailable {
        HttpURLConnection connection = null;
        try {
            byte[] payload = ReferralJson.stringify(body(extra)).getBytes(StandardCharsets.UTF_8);
            // ⚠️ `URL#openConnection` direct, voulu : le cœur ne dépend que de `java.*` (tests JVM,
            // § 8.6). Chromium le signale (`UseNetworkAnnotations`) — l'exception est levée sur la
            // méthode, avec cette raison.
            connection = (HttpURLConnection) new URL(baseURL + path).openConnection();
            int timeout = bounded ? readTimeout : writeTimeout;
            connection.setConnectTimeout(timeout);
            connection.setReadTimeout(timeout);
            connection.setRequestMethod("POST");
            connection.setUseCaches(false);
            connection.setDoOutput(true);
            connection.setFixedLengthStreamingMode(payload.length);
            connection.setRequestProperty("Content-Type", "application/json");
            if (headers != null) {
                for (Map.Entry<String, String> header : headers.entrySet()) {
                    connection.setRequestProperty(header.getKey(), header.getValue());
                }
            }
            try (OutputStream out = connection.getOutputStream()) {
                out.write(payload);
            }
            int code = connection.getResponseCode();
            if (code < 200 || code >= 300) throw new ReferralUnavailable(code);
            String text;
            try (InputStream in = connection.getInputStream()) {
                text = readAll(in);
            }
            return ReferralJson.parseObject(text);
        } catch (ReferralUnavailable e) {
            throw e;
        } catch (IOException | ReferralJson.JsonException | RuntimeException e) {
            throw new ReferralUnavailable(null);
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
}
