/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.ReferralAccount;

/**
 * Le rangement du compte dev&din sur l'appareil — pendant de {@code ReferralAccountStore} (iOS : le
 * trousseau). Le contrôleur le reçoit de sa {@code Platform} : le navigateur donne {@link
 * ReferralAccountKeystore}, l'aperçu à l'émulateur un faux en mémoire.
 *
 * <p>🔴 Deux natures, deux endroits (docs/PARRAINAGE.md § 7.1, « Le jeton ») :
 *
 * <ul>
 *   <li><b>le jeton de session et l'adresse</b> — chiffrés, ⛔ jamais en clair dans les préférences,
 *       ⛔ jamais dans un journal : le jeton vaut une session dev&din d'un an ;
 *   <li><b>l'identifiant du compte</b>, seul, EN CLAIR : il n'a rien de secret (c'est le sujet du
 *       parrainage, envoyé à chaque appel), et il doit rester lisible quand le coffre ne l'est pas
 *       — sinon le sujet retomberait EN SILENCE sur l'appareil, et la personne verrait son code,
 *       ses invitations et ses mois « disparaître » sans s'être déconnectée.
 * </ul>
 *
 * <p>⚠️ Une session ne se recopie pas d'un appareil à l'autre : chacun se connecte (et se
 * déconnecte) pour lui-même.
 */
public interface ReferralAccountStore {
    /** Ce qui est rangé. */
    final class Stored {
        /** ⚠️ {@code email} et {@code name} sont {@code null} quand le coffre est illisible. */
        public final ReferralAccount account;

        /** {@code null} quand le coffre est illisible : on sait QUI, on ne peut plus parler en son nom. */
        public final @Nullable String token;

        public Stored(ReferralAccount account, @Nullable String token) {
            this.account = account;
            this.token = token;
        }
    }

    /**
     * L'identifiant du compte connecté, ou {@code null}. ⭐ Se lit SANS le coffre, donc sur le fil de
     * l'interface : c'est lui qui fait le sujet au démarrage.
     */
    @Nullable
    String accountId();

    /**
     * Le compte et son jeton, ou {@code null} sans compte. ⚠️ Déchiffre : ⛔ pas sur le fil de
     * l'interface. ⛔ Ne lève jamais — un coffre illisible rend un jeton {@code null}.
     */
    @Nullable
    Stored load();

    /** {@code false} = rien n'a été rangé (et rien ne l'est à moitié) : la connexion échoue. */
    boolean save(ReferralAccount account, String token);

    /** Tout oublier. ⛔ Ne dépend de rien (ni réseau, ni coffre lisible) et ne lève jamais. */
    void clear();
}
