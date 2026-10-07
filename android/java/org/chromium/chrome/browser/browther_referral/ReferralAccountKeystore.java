/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.ReferralAccount;
import org.chromium.chrome.browser.browther_referral.core.ReferralJson;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.Key;
import java.security.KeyStore;
import java.util.LinkedHashMap;
import java.util.Map;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Le compte dev&din rangé sur Android : le jeton et l'adresse chiffrés par une clé de l'<b>Android
 * Keystore</b> (AES-256-GCM), l'identifiant du compte en clair à côté — voir {@link
 * ReferralAccountStore} pour le pourquoi des deux.
 *
 * <ul>
 *   <li>🔴 La clé ne sort JAMAIS du Keystore (matériel quand l'appareil en a un) : ce qui est écrit
 *       dans les préférences est illisible sans elle, y compris dans une sauvegarde ou sur un
 *       appareil où l'on recopierait le fichier. C'est le pendant du {@code
 *       …AfterFirstUnlockThisDeviceOnly} d'iOS : la session ne suit pas vers un autre appareil.
 *   <li>🔴 L'identifiant en clair est LIÉ au secret (donnée authentifiée de GCM) : un secret
 *       recopié sous un autre identifiant ne s'ouvre pas.
 *   <li>⛔ Aucun repli en clair : si le Keystore refuse, {@link #save} rend {@code false} et la
 *       connexion échoue — on ne range jamais un jeton lisible.
 *   <li>⛔ Rien de tout ceci n'est journalisé, pas même une exception (son message pourrait porter
 *       un fragment).
 * </ul>
 *
 * <p>⚠️ Pas d'authentification de l'utilisateur sur la clé (ni empreinte, ni code) : le statut se
 * relit au retour au premier plan, sans rien demander.
 */
public final class ReferralAccountKeystore implements ReferralAccountStore {
    /** ⚠️ Un identifiant, ⛔ jamais le jeton. */
    private static final String KEY_ID = "browther.referral.account-id";

    /** Le jeton et l'adresse, chiffrés : longueur du vecteur, vecteur, puis le texte scellé. */
    private static final String KEY_SECRET = "browther.referral.account-secret";

    private static final String KEYSTORE = "AndroidKeyStore";
    private static final String KEY_ALIAS = "browther.referral.account";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int TAG_BITS = 128;

    private final SharedPreferences mPrefs;

    public ReferralAccountKeystore(SharedPreferences prefs) {
        mPrefs = prefs;
    }

    @Override
    public @Nullable String accountId() {
        try {
            String id = mPrefs.getString(KEY_ID, null);
            return id == null || id.isEmpty() ? null : id;
        } catch (RuntimeException e) {
            return null;
        }
    }

    @Override
    public @Nullable Stored load() {
        String id = accountId();
        if (id == null) return null;
        String token = null;
        String email = null;
        String name = null;
        try {
            String sealed = mPrefs.getString(KEY_SECRET, null);
            SecretKey key = sealed == null ? null : key(false);
            if (sealed != null && key != null) {
                byte[] blob = Base64.decode(sealed, Base64.NO_WRAP);
                int ivLength = blob.length == 0 ? -1 : blob[0];
                if (ivLength > 0 && blob.length > 1 + ivLength) {
                    Cipher cipher = Cipher.getInstance(TRANSFORMATION);
                    cipher.init(
                            Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, blob, 1, ivLength));
                    cipher.updateAAD(id.getBytes(StandardCharsets.UTF_8));
                    byte[] plain = cipher.doFinal(blob, 1 + ivLength, blob.length - 1 - ivLength);
                    ReferralJson.Obj secret =
                            ReferralJson.parseObject(new String(plain, StandardCharsets.UTF_8));
                    token = secret.optString("token");
                    email = secret.optString("email");
                    name = secret.optString("name");
                }
            }
        } catch (GeneralSecurityException
                | IOException
                | ReferralJson.JsonException
                | RuntimeException e) {
            // Coffre illisible (clé perdue, Keystore en panne, secret abîmé) : on garde QUI c'est
            // — l'identifiant suffit à rester sur le sujet du compte —, sans jeton. ⛔ On ne
            // déconnecte personne sur un « on ne sait pas ».
            token = null;
            email = null;
            name = null;
        }
        if (token != null && token.isEmpty()) token = null;
        return new Stored(new ReferralAccount(id, email, name), token);
    }

    @Override
    public boolean save(ReferralAccount account, String token) {
        if (account.userId.isEmpty() || token.isEmpty()) return false;
        Map<String, Object> secret = new LinkedHashMap<>();
        secret.put("token", token);
        secret.put("email", account.email);
        secret.put("name", account.name);
        byte[] plain = ReferralJson.stringify(secret).getBytes(StandardCharsets.UTF_8);
        byte[] aad = account.userId.getBytes(StandardCharsets.UTF_8);
        String sealed = seal(plain, aad);
        if (sealed == null) {
            // Une clé devenue inutilisable (restauration, changement de matériel) : on en refait
            // une, UNE fois. Ce qu'elle scellait était de toute façon illisible.
            forgetKey();
            sealed = seal(plain, aad);
        }
        if (sealed == null) return false;
        try {
            // ⚠️ `commit`, ⛔ pas `apply` : on est hors du fil de l'interface, et « rangé » doit
            // être VRAI avant que le sujet ne devienne le compte. Les deux valeurs partent ensemble.
            return mPrefs.edit().putString(KEY_ID, account.userId).putString(KEY_SECRET, sealed).commit();
        } catch (RuntimeException e) {
            return false;
        }
    }

    @Override
    public void clear() {
        try {
            // La clé reste dans le Keystore : sans le secret, elle n'ouvre rien.
            mPrefs.edit().remove(KEY_ID).remove(KEY_SECRET).apply();
        } catch (RuntimeException e) {
            // ⛔ La déconnexion ne dépend de rien.
        }
    }

    /** Le texte scellé, prêt à ranger — {@code null} si le Keystore refuse. */
    private static @Nullable String seal(byte[] plain, byte[] aad) {
        try {
            SecretKey key = key(true);
            if (key == null) return null;
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            // ⚠️ Le vecteur est tiré par le Keystore (il refuse qu'on le lui fournisse).
            cipher.init(Cipher.ENCRYPT_MODE, key);
            cipher.updateAAD(aad);
            byte[] text = cipher.doFinal(plain);
            byte[] iv = cipher.getIV();
            if (iv == null || iv.length == 0 || iv.length > Byte.MAX_VALUE) return null;
            byte[] blob = new byte[1 + iv.length + text.length];
            blob[0] = (byte) iv.length;
            System.arraycopy(iv, 0, blob, 1, iv.length);
            System.arraycopy(text, 0, blob, 1 + iv.length, text.length);
            return Base64.encodeToString(blob, Base64.NO_WRAP);
        } catch (GeneralSecurityException | IOException | RuntimeException e) {
            return null;
        }
    }

    /** La clé du coffre ; {@code create} = la fabriquer si elle n'existe pas encore. */
    private static @Nullable SecretKey key(boolean create)
            throws GeneralSecurityException, IOException {
        KeyStore store = KeyStore.getInstance(KEYSTORE);
        store.load(null);
        Key existing = store.getKey(KEY_ALIAS, null);
        if (existing instanceof SecretKey) return (SecretKey) existing;
        if (!create) return null;
        KeyGenerator generator =
                KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE);
        generator.init(
                new KeyGenParameterSpec.Builder(
                                KEY_ALIAS,
                                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .build());
        return generator.generateKey();
    }

    private static void forgetKey() {
        try {
            KeyStore store = KeyStore.getInstance(KEYSTORE);
            store.load(null);
            store.deleteEntry(KEY_ALIAS);
        } catch (GeneralSecurityException | IOException | RuntimeException e) {
            // Rien à défaire.
        }
    }
}
