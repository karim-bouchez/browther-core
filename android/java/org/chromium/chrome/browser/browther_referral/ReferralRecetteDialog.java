/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.app.Dialog;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.RecetteState;
import org.chromium.chrome.browser.browther_referral.core.ReminderCase;

import java.time.Instant;

/**
 * 🧪 Recetter pour de vrai : un outil qui POSE l'état — docs/PARRAINAGE.md § 12.18 ; port de
 * {@code ReferralRecetteView.swift}. Paramètres › « Browther — recette » › « Parrainage —
 * recette » (build de dev, ou options développeur débloquées). Interne, non traduit.
 *
 * <ul>
 *   <li>Poser une situation (service + appareil) : un scénario en un geste, avec N invitations
 *       validées / en cours. ⭐ Il ouvre l'écran du scénario DIRECTEMENT (verrou du jour levé,
 *       mérite posé) — et il DIT pourquoi rien ne s'est ouvert.
 *   <li>🔴 Le jeton d'administration se SAISIT ici et reste sur l'appareil — ⛔ jamais une
 *       constante de build.
 *   <li>Revoir un écran : ⛔ n'écrit rien (§ 12.7).
 * </ul>
 */
public final class ReferralRecetteDialog extends Dialog {
    /** Le temps que la recette se ferme avant d'ouvrir l'écran par-dessus le navigateur. */
    private static final long AFTER_CLOSE_MS = 400;

    private final Activity mActivity;
    private final BrowtherReferralController mController = BrowtherReferralController.get();
    private final Handler mMain = new Handler(Looper.getMainLooper());
    private int mValidated;
    private int mInstalled;
    private boolean mBusy;
    private @Nullable TextView mSummary;
    private @Nullable TextView mMessage;

    public ReferralRecetteDialog(Activity activity) {
        super(activity, android.R.style.Theme_DeviceDefault_DayNight);
        mActivity = activity;
    }

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        mController.boot();
        ScrollView scroll = new ScrollView(getContext());
        LinearLayout column = ReferralUi.column(getContext());
        int pad = ReferralUi.dp(getContext(), 16);
        column.setPadding(pad, pad, pad, pad);
        scroll.addView(column);
        setContentView(scroll);
        Window window = getWindow();
        if (window != null) {
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
        }

        LinearLayout top = ReferralUi.row(getContext());
        TextView title = new TextView(getContext());
        title.setText("Parrainage — recette");
        title.setTextSize(20);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        top.addView(title, new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1));
        top.addView(button("Fermer", this::dismiss));
        column.addView(top);

        // -------------------- Où j'en suis --------------------
        column.addView(header("Où j'en suis"));
        mSummary = new TextView(getContext());
        mSummary.setTypeface(Typeface.MONOSPACE);
        mSummary.setTextSize(12);
        mSummary.setTextIsSelectable(true);
        column.addView(mSummary);
        column.addView(button("Relire le statut", () -> {
            mController.refresh();
            mMain.postDelayed(this::updateSummary, 1_500);
        }));

        // -------------------- Poser une situation --------------------
        column.addView(header("Poser une situation"));
        EditText token = new EditText(getContext());
        token.setHint("Jeton d'administration (ADMIN_API_TOKEN)");
        token.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        String saved = mController.recetteToken();
        if (saved != null) token.setText(saved);
        column.addView(token);
        column.addView(stepper("Invitations validées", 12, true));
        column.addView(stepper("Invitations en cours", 5, false));
        CheckBox extras = new CheckBox(getContext());
        extras.setText("Faire comme si Sawtunaa était finalisé");
        extras.setChecked(mController.recetteExtrasReleased());
        extras.setOnCheckedChangeListener(
                (view, checked) -> {
                    mController.setRecetteExtrasReleased(checked);
                    updateSummary();
                });
        column.addView(extras);
        for (Scenario scenario : Scenario.values()) {
            column.addView(button(scenario.label, () -> apply(scenario, token.getText().toString())));
        }
        mMessage = new TextView(getContext());
        mMessage.setTextSize(13);
        column.addView(mMessage);
        column.addView(note("Le service est remplacé en entier (couverture, invitations, abonnement), "
                + "puis l'écran du scénario s'ouvre sur le navigateur. « Neuf » n'annonce rien tant "
                + "que Sawtunaa n'est pas finalisé : cocher la case au-dessus."));

        // -------------------- Cet appareil --------------------
        column.addView(header("Cet appareil"));
        column.addView(button("Provoquer maintenant (mérite posé)", () -> {
            mController.liftDayLockForRecette();
            provoke();
        }));
        column.addView(button("Compter aujourd'hui comme jour « par défaut »", () -> {
            mController.recordDefaultDayForRecette();
            say("Jour compté : il part au service si ce sujet a un parrain.");
        }));
        column.addView(button("Lever le verrou du jour", () -> {
            mController.liftDayLockForRecette();
            say("Verrou du jour levé.");
        }));
        column.addView(button("Rejouer la démo de la jauge", () -> {
            mController.resetGaugeUnderstoodForRecette();
            say("La jauge rejouera sa démo.");
        }));
        column.addView(button("Oublier ce que j'ai vu (annonce, rappels, circuit)", () -> {
            mController.forgetPromptForRecette();
            say("Oublié.");
        }));
        column.addView(button("Repartir d'un appareil neuf", () -> {
            mController.setRecetteIdentity(true);
            say("Nouvelle identité : le service la découvre maintenant.");
        }));
        column.addView(button("Revenir à la vraie identité", () -> {
            mController.setRecetteIdentity(false);
            say("Vraie identité rétablie.");
        }));

        // -------------------- Revoir un écran --------------------
        column.addView(header("Revoir un écran (n'écrit rien)"));
        String until = "2026-12-01T10:00:00.000Z";
        preview(column, "O — le code d'un proche", ReferralScreen.welcome());
        preview(column, "0 — l'annonce", ReferralScreen.announce());
        preview(column, "1 — J−3 (première fin)", ReferralScreen.ending(3));
        preview(column, "2 — J0 (tombé)", ReferralScreen.paused(false));
        preview(column, "2 — J0 (« Débloquer »)", ReferralScreen.paused(true));
        preview(column, "2b — les trois façons (fermé)", ReferralScreen.support(true));
        preview(column, "3 — rappel « en bonne voie »",
                ReferralScreen.reminder(3, ReminderCase.IN_PROGRESS));
        preview(column, "3 — rappel « fin de mois gagnés »",
                ReferralScreen.reminder(10, ReminderCase.EARNED_MONTHS_ENDING));
        preview(column, "3 — rappel « abonnement annulé »",
                ReferralScreen.reminder(3, ReminderCase.SUBSCRIPTION_CANCELLED));
        preview(column, "4 — inviter (seul)", ReferralScreen.invite(false));
        preview(column, "7 — soutenir (porte factice)", ReferralScreen.billing());
        preview(column, "7 ter — c'est cadeau !", ReferralScreen.gift(true, until));
        preview(column, "7 ter — déjà offert", ReferralScreen.gift(false, null));
        preview(column, "8 — invitation validée", ReferralScreen.validated(2, until, false));
        preview(column, "8 — à vie", ReferralScreen.validated(1, null, true));
        preview(column, "8 bis — merci (filleul)", ReferralScreen.refereeDone());
        column.addView(button("Toast 0 bis — « C'est noté »", () -> afterClose(
                () -> mController.announceLaterToast(mActivity))));
        column.addView(button("Toast — garde du retrait de la musique", () -> afterClose(
                () -> ReferralToast.show(
                        mActivity,
                        ReferralStrings.get(mActivity, "locked.musicRemoval"),
                        ReferralStrings.get(mActivity, "locked.body"),
                        ReferralStrings.get(mActivity, "locked.cta"),
                        () -> {},
                        false))));
        updateSummary();
    }

    private void updateSummary() {
        if (mSummary != null) mSummary.setText(mController.debugSummary());
    }

    private void say(String message) {
        if (mMessage != null) mMessage.setText(message);
        updateSummary();
    }

    private void apply(Scenario scenario, String token) {
        if (mBusy) return;
        if (token.isEmpty()) {
            say("Colle d'abord le jeton d'administration.");
            return;
        }
        mController.setRecetteToken(token);
        mBusy = true;
        say("…");
        mController.applyRecette(
                token,
                scenario.state(mValidated, mInstalled),
                ok -> {
                    mBusy = false;
                    if (!ok) {
                        say("Le service a refusé (jeton ? réseau ?).");
                        return;
                    }
                    mController.liftDayLockForRecette();
                    provoke();
                });
    }

    /** Ferme la recette, pose le mérite, tente — et DIT ce qui s'est passé (§ 12.18). */
    private void provoke() {
        afterClose(
                () -> {
                    mController.forceMeritForRecette();
                    BrowtherReferralController.Attempt attempt =
                            mController.attemptSolicitation(mActivity, Instant.now(), true);
                    if (attempt == BrowtherReferralController.Attempt.SHOWN) return;
                    ReferralToast.show(mActivity, "Parrainage — recette", why(attempt), null, null, false);
                });
    }

    private String why(BrowtherReferralController.Attempt attempt) {
        switch (attempt) {
            case NONE:
                return mController.extrasReleased()
                        ? "Rien n'est dû pour cette situation."
                        : "Rien n'est dû : l'annonce dort tant que Sawtunaa n'est pas finalisé. "
                                + "Cocher « Faire comme si Sawtunaa était finalisé ».";
            case LOCKED_TODAY:
                return "Une sollicitation a déjà eu lieu aujourd'hui (verrou du jour).";
            case BUSY:
                return "Le navigateur n'a pas la main (une autre fenêtre est ouverte).";
            case UNKNOWN:
            default:
                return "Statut inconnu : le service n'a pas encore répondu.";
        }
    }

    private void afterClose(Runnable action) {
        dismiss();
        mMain.postDelayed(action, AFTER_CLOSE_MS);
    }

    private void preview(LinearLayout column, String label, ReferralScreen screen) {
        column.addView(button(label, () -> afterClose(
                () -> BrowtherReferralPresenter.present(
                        mActivity, screen, BrowtherReferralPresenter.Source.USER, true))));
    }

    private TextView header(String text) {
        TextView view = new TextView(getContext());
        view.setText(text);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setTextSize(16);
        view.setPadding(0, ReferralUi.dp(getContext(), 20), 0, ReferralUi.dp(getContext(), 6));
        return view;
    }

    private TextView note(String text) {
        TextView view = new TextView(getContext());
        view.setText(text);
        view.setTextSize(12);
        view.setAlpha(0.7f);
        return view;
    }

    private Button button(String label, Runnable action) {
        Button button = new Button(getContext());
        button.setText(label);
        button.setAllCaps(false);
        button.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        button.setOnClickListener(v -> action.run());
        return button;
    }

    private View stepper(String label, int max, boolean validated) {
        LinearLayout row = ReferralUi.row(getContext());
        TextView text = new TextView(getContext());
        Runnable render = () -> text.setText(label + " : " + (validated ? mValidated : mInstalled));
        render.run();
        row.addView(text, new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1));
        row.addView(button("−", () -> {
            if (validated) mValidated = Math.max(0, mValidated - 1);
            else mInstalled = Math.max(0, mInstalled - 1);
            render.run();
        }));
        row.addView(button("+", () -> {
            if (validated) mValidated = Math.min(max, mValidated + 1);
            else mInstalled = Math.min(max, mInstalled + 1);
            render.run();
        }));
        return row;
    }

    /** Les situations — les mêmes qu'iOS. */
    private enum Scenario {
        FRESH("Neuf (avant l'annonce)"),
        RUNNING("Mois en cours (20 j)"),
        J10("J−10"),
        J3("J−3"),
        J0("J0 (tombée hier)"),
        SUBSCRIBED("Abonné"),
        CANCELLED("Résilié (3 j)"),
        LIFETIME("À vie");

        final String label;

        Scenario(String label) {
            this.label = label;
        }

        RecetteState state(int validated, int installed) {
            RecetteState state;
            switch (this) {
                case FRESH:
                    state = new RecetteState(false, null);
                    break;
                case RUNNING:
                    state = new RecetteState(true, 20);
                    break;
                case J10:
                    state = new RecetteState(true, 10);
                    break;
                case J3:
                    state = new RecetteState(true, 3);
                    break;
                case J0:
                    state = new RecetteState(true, -1);
                    break;
                case SUBSCRIBED:
                    state = new RecetteState(true, null);
                    state.subscription = RecetteState.Subscription.ACTIVE;
                    state.subscriptionDaysLeft = 30;
                    break;
                case CANCELLED:
                    state = new RecetteState(true, null);
                    state.subscription = RecetteState.Subscription.CANCELLED;
                    state.subscriptionDaysLeft = 3;
                    break;
                case LIFETIME:
                default:
                    state = new RecetteState(true, null);
                    state.lifetime = true;
                    break;
            }
            state.validated = validated;
            state.installed = installed;
            return state;
        }
    }
}
