/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;

import androidx.annotation.Nullable;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Ouvre les fenêtres du parrainage — pendant de {@code BrowtherReferralPresenter.swift}.
 *
 * <p>⭐⭐ <b>{@link #countShown} est l'UNIQUE émission de {@code paywall_shown}</b> (§ 13.2 du doc
 * commun) : elle est appelée par ce qui POSE une fenêtre — {@link #present} pour les feuilles,
 * {@link FlowModel#show} pour la pile, l'écran Parrainage à sa création, le toast de la garde —,
 * ⛔ jamais par un écran. ⛔ Un retour ne compte pas, ni un aperçu. Verrouillé par
 * {@code private/scripts/android-referral-tests/analytics_check.py}.
 */
public final class BrowtherReferralPresenter {
    private BrowtherReferralPresenter() {}

    /**
     * D'où vient l'affichage d'une fenêtre (§ 13.2) : une sollicitation ({@code prompt}), le
     * circuit rouvert ({@code circuit}), une bonne nouvelle ({@code notice}), un geste dans le flow
     * ({@code flow}), la pause d'une fonctionnalité ({@code locked}), la personne elle-même ({@code
     * user} : menu, Paramètres, panneau) ou l'issue d'un paiement ({@code purchase}).
     */
    public enum Source {
        PROMPT("prompt"),
        CIRCUIT("circuit"),
        NOTICE("notice"),
        FLOW("flow"),
        LOCKED("locked"),
        USER("user"),
        PURCHASE("purchase");

        public final String wire;

        Source(String wire) {
            this.wire = wire;
        }
    }

    /** Ouvre un écran du flow. {@code preview} = aperçu de recette : ⛔ n'écrit rien, ⛔ ne compte rien. */
    public static void present(
            @Nullable Activity activity, ReferralScreen screen, Source source, boolean preview) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return;
        if (screen.isSheet()) {
            new ReferralSheetDialog(activity, screen, preview).show();
            countShown(screen.analyticsName(), source, preview, null);
        } else {
            // La pile compte sa première fenêtre elle-même (`FlowModel.show`).
            new ReferralFlowDialog(activity, screen, source, preview).show();
        }
    }

    /** L'unique émission de {@code paywall_shown}. */
    public static void countShown(
            String screen, Source source, boolean preview, @Nullable Map<String, Object> extra) {
        if (preview) return;
        Map<String, Object> properties = extra == null ? new HashMap<>() : new HashMap<>(extra);
        properties.put("screen", screen);
        properties.put("source", source.wire);
        BrowtherReferralController.get().track("paywall_shown", properties);
    }

    /**
     * Écran 6 — Parrainage, depuis n'importe quel « Inviter un proche » hors du circuit des trois
     * façons (§ 12.15) : la MÊME page que dans les Paramètres.
     */
    public static void presentHome(@Nullable Activity activity, Source source) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return;
        new ReferralHomeDialog(activity, source).show();
    }

    // -------------------- La pile plein écran --------------------

    /**
     * La pile des fenêtres plein écran (O, 0, 2, 2b, 4 par-dessus 2b, 7, cadeau, Merci) — pendant de
     * {@code ReferralFlowModel}. ⚠️ Sur Android, seule la fenêtre du DESSUS est dessinée (§ 12.38 :
     * une pile de couches laisse fuir le pied de celle du dessous) ; la pile n'est qu'un état.
     */
    public static final class FlowModel {
        /** Redessine la fenêtre du dessus ; ferme le flow quand la pile se vide. */
        public interface Host {
            void render(ReferralScreen top, boolean forward);

            void dismiss();
        }

        private final List<ReferralScreen> mStack = new ArrayList<>();
        public final boolean preview;
        private final Host mHost;

        public FlowModel(ReferralScreen root, Source source, boolean preview, Host host) {
            this.preview = preview;
            mHost = host;
            show(Collections.singletonList(root), source, true);
        }

        public ReferralScreen top() {
            return mStack.get(mStack.size() - 1);
        }

        public int depth() {
            return mStack.size();
        }

        /**
         * ⭐⭐ Le seul endroit qui pose la pile — donc qui compte ses fenêtres (§ 13.2). {@code
         * source == null} : rien de NEUF n'est montré (le même écran dans un autre état).
         */
        private void show(List<ReferralScreen> next, @Nullable Source source, boolean forward) {
            mStack.clear();
            mStack.addAll(next);
            mHost.render(top(), forward);
            if (source != null) countShown(top().analyticsName(), source, preview, null);
        }

        /** Pose une fenêtre PAR-DESSUS l'actuelle (« Retour » y ramène). */
        public void push(ReferralScreen screen) {
            List<ReferralScreen> next = new ArrayList<>(mStack);
            next.add(screen);
            show(next, Source.FLOW, true);
        }

        /** ⛔ Un RETOUR ne compte pas : la fenêtre du dessous a déjà été vue. */
        public void back() {
            if (mStack.size() <= 1) {
                mHost.dismiss();
                return;
            }
            mStack.remove(mStack.size() - 1);
            mHost.render(top(), false);
        }

        /**
         * Remplace la fenêtre du dessus : comptée si c'est un AUTRE écran (J0 → les trois façons),
         * pas si c'est le même dans un autre état (4 partagé).
         */
        public void replaceTop(ReferralScreen screen) {
            boolean isNew = !top().analyticsName().equals(screen.analyticsName());
            List<ReferralScreen> next = new ArrayList<>(mStack);
            next.set(next.size() - 1, screen);
            show(next, isNew ? Source.FLOW : null, isNew);
        }

        /**
         * Remplace toute la pile par une fenêtre seule (« Merci », « C'est cadeau ! » : ⛔ jamais
         * la fenêtre d'où l'on est parti, § 12.17).
         */
        public void replaceAll(ReferralScreen screen, Source source) {
            show(Collections.singletonList(screen), source, true);
        }

        public void dismiss() {
            mHost.dismiss();
        }

        /** La fenêtre du dessus ne se ferme-t-elle que par ses boutons ? (§ 12.14) */
        public boolean isTopLocked() {
            return isLocked(mStack);
        }

        static boolean isLocked(List<ReferralScreen> stack) {
            if (stack.isEmpty()) return false;
            ReferralScreen top = stack.get(stack.size() - 1);
            List<ReferralScreen> below = stack.subList(0, stack.size() - 1);
            switch (top.kind) {
                case WELCOME:
                case ANNOUNCE:
                    return true;
                case PAUSED:
                    return !top.chosen;
                case SUPPORT:
                    return top.locked;
                case INVITE:
                    if (top.shared) return false;
                    return !below.isEmpty() && isLocked(below);
                case BILLING:
                    // Ce qu'on ouvre par-dessus une fenêtre verrouillée l'est aussi (§ 12.16).
                    return !below.isEmpty() && isLocked(below);
                default:
                    return false;
            }
        }
    }
}
