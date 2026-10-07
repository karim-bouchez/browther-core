/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.text.Editable;
import android.text.InputFilter;
import android.text.InputType;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.ReferralDeletability;
import org.chromium.chrome.browser.browther_referral.core.ReferralDeletion;
import org.chromium.chrome.browser.browther_referral.core.ReferralDeletionCode;
import org.chromium.chrome.browser.browther_referral.core.ReferralDeletionOutcome;

import java.util.ArrayList;
import java.util.List;

/**
 * 🔴 <b>La suppression du compte vit ICI, dans l'app</b> (Google, Apple 5.1.1(v)), en deux temps :
 * ce qui part, puis le code à six chiffres reçu par e-mail. Elle supprime le compte pour TOUTES les
 * apps dev&din, et l'écran le dit avant de demander le code. ⛔ Ne jamais la cacher ni la renvoyer
 * vers un site. Port de {@code ReferralAccountDeletion} ({@code ReferralAccountView.swift}).
 *
 * <p>⭐ <b>Un refus se dit AVANT le code</b> : en ouvrant « Supprimer mon compte », on demande au
 * serveur si ce compte peut l'être d'ici ({@code checkAccountDeletable}) — un compte bloqué voit
 * pourquoi, sans rouge ni bouton, et ne reçoit aucun code. ⚠️ Sans réponse, on n'ouvre RIEN. Le
 * serveur garde le dernier mot ({@code USED_ELSEWHERE}).
 *
 * <p>⚠️ Un état d'attente PAR bouton ({@link Busy}) : sinon tous tournent quand on en touche un. ⛔
 * Pas de validation automatique au sixième chiffre : supprimer un compte se CONFIRME, d'un bouton
 * rouge plein.
 */
public final class ReferralAccountDeletion extends LinearLayout {
    /** Ce que la page du compte fait pour la suppression. */
    public interface Host {
        /** Une suppression est en route (ou ne l'est plus) : ⛔ on ne se déconnecte pas pendant. */
        void onDeletionBusy(boolean busy);

        /** Le compte est supprimé — ⚠️ cette vue n'est déjà plus à l'écran : c'est la page qui le dit. */
        void onAccountDeleted();

        /** Le champ du code a le focus : la page le fait monter au-dessus du clavier. */
        void onFieldFocused(View field);
    }

    private enum Step {
        CLOSED,
        WARNING,
        CODE,
        /** Le compte ne se supprime pas d'ici — {@link #mApps} nomme les apps qu'on connaît. */
        BLOCKED
    }

    private enum Busy {
        CHECK,
        SEND,
        DELETE
    }

    private final ReferralUi.Palette mP;
    private final Host mHost;
    private final BrowtherReferralController mController = BrowtherReferralController.get();
    private final int mDanger;

    private Step mStep = Step.CLOSED;
    private @Nullable Busy mWorking;
    private String mDestination = "";
    private List<String> mApps = new ArrayList<>();

    private @Nullable TextView mOpenLink;
    private @Nullable ProgressBar mOpenSpinner;
    private @Nullable ReferralUi.BusyButton mSendButton;
    private @Nullable ReferralUi.BusyButton mConfirmButton;
    private @Nullable EditText mCodeField;
    private @Nullable TextView mProblem;
    private @Nullable View mCancel;

    public ReferralAccountDeletion(Context context, ReferralUi.Palette palette, Host host) {
        super(context);
        mP = palette;
        mHost = host;
        mDanger = ReferralUi.danger(palette);
        setOrientation(VERTICAL);
        build();
    }

    /** Une étape du dessus à refermer avant de quitter la page ? (le geste retour) */
    public boolean isOpen() {
        return mStep != Step.CLOSED;
    }

    /** Referme l'étape en cours — {@code false} si une suppression est en route (on ne la lâche pas). */
    public boolean closeIfIdle() {
        if (mWorking != null) return false;
        close();
        return true;
    }

    // -------------------- Le dessin --------------------

    private void build() {
        Context context = getContext();
        removeAllViews();
        mOpenLink = null;
        mOpenSpinner = null;
        mSendButton = null;
        mConfirmButton = null;
        mCodeField = null;
        mCancel = null;
        TextView problem = ReferralUi.text(context, 13, ReferralUi.REGULAR, mDanger);
        problem.setVisibility(GONE);
        mProblem = problem;
        switch (mStep) {
            case BLOCKED:
                addView(blocked(), ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
                break;
            case WARNING:
                addView(
                        danger(warning(), problem),
                        ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
                break;
            case CODE:
                addView(
                        danger(codeStep(), problem),
                        ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
                break;
            case CLOSED:
            default:
                closed(problem);
                break;
        }
        update();
    }

    private void closed(TextView problem) {
        Context context = getContext();
        FrameLayout holder = new FrameLayout(context);
        TextView link =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "account.delete"),
                        15,
                        ReferralUi.MEDIUM,
                        mDanger);
        link.setPaintFlags(link.getPaintFlags() | Paint.UNDERLINE_TEXT_FLAG);
        link.setGravity(Gravity.CENTER);
        link.setTextAlignment(TEXT_ALIGNMENT_CENTER);
        int padH = ReferralUi.dp(context, 12);
        link.setPadding(padH, 0, padH, 0);
        link.setMinHeight(ReferralUi.dp(context, 44));
        link.setBackground(
                ReferralUi.pressable(
                        null, ReferralUi.withAlpha(mDanger, 0.12f), ReferralUi.dp(context, 10)));
        link.setClickable(true);
        link.setFocusable(true);
        link.setOnClickListener(v -> open());
        holder.addView(link, ReferralUi.frame(ReferralUi.WRAP, ReferralUi.WRAP, Gravity.CENTER));
        ProgressBar spinner = new ProgressBar(context);
        spinner.setIndeterminate(true);
        spinner.setIndeterminateTintList(ColorStateList.valueOf(mP.text2));
        spinner.setVisibility(GONE);
        int size = ReferralUi.dp(context, 22);
        holder.addView(spinner, ReferralUi.frame(size, size, Gravity.CENTER));
        mOpenLink = link;
        mOpenSpinner = spinner;
        addView(holder, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        problem.setGravity(Gravity.CENTER_HORIZONTAL);
        problem.setTextAlignment(TEXT_ALIGNMENT_CENTER);
        addView(
                problem,
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 8)));
    }

    /** ⚠️ Ni rouge ni bouton de suppression : il n'y a rien à supprimer d'ici. */
    private View blocked() {
        Context context = getContext();
        LinearLayout box = box(mP.line);
        box.addView(head());
        String text =
                mApps.isEmpty()
                        ? ReferralStrings.get(context, "account.deleteElsewhereUnknown")
                        : ReferralStrings.fill(
                                ReferralStrings.get(context, "account.deleteElsewhere"),
                                "apps",
                                TextUtils.join(", ", mApps));
        box.addView(
                ReferralUi.text(context, text, 15, ReferralUi.REGULAR, mP.text2),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 10)));
        box.addView(
                textLink(ReferralStrings.get(context, "common.close"), this::close),
                linkParams());
        return box;
    }

    private LinearLayout warning() {
        Context context = getContext();
        LinearLayout column = ReferralUi.column(context);
        column.addView(
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "account.deleteBody"),
                        15,
                        ReferralUi.REGULAR,
                        mP.text2),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        // ⚠️ Un abonnement en cours n'est PAS résilié par la suppression.
        column.addView(
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "account.deleteSubscription"),
                        13,
                        ReferralUi.REGULAR,
                        mP.text2),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 12)));
        // Un geste qui supprime : cerclé pour demander le code, PLEIN pour supprimer.
        mSendButton =
                ReferralUi.busyOutline(
                        context,
                        ReferralStrings.get(context, "account.deleteSend"),
                        0,
                        mDanger,
                        ReferralUi.withAlpha(mDanger, 0.6f),
                        this::askCode);
        column.addView(
                mSendButton,
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 12)));
        return column;
    }

    private LinearLayout codeStep() {
        Context context = getContext();
        LinearLayout column = ReferralUi.column(context);
        column.addView(
                ReferralUi.text(
                        context,
                        ReferralStrings.fill(
                                ReferralStrings.get(context, "account.deleteSent"),
                                "destination",
                                mDestination),
                        13,
                        ReferralUi.REGULAR,
                        mP.text2),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        EditText field = codeField(context, mP);
        field.addTextChangedListener(
                new TextWatcher() {
                    @Override
                    public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

                    @Override
                    public void onTextChanged(CharSequence s, int start, int before, int count) {}

                    @Override
                    public void afterTextChanged(Editable s) {
                        setProblem(null);
                        update();
                    }
                });
        field.setOnFocusChangeListener(
                (v, focused) -> {
                    if (focused) mHost.onFieldFocused(v);
                });
        mCodeField = field;
        column.addView(
                field,
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 12)));
        // ⛔ Pas de validation automatique au sixième chiffre : supprimer un compte se CONFIRME.
        mConfirmButton =
                ReferralUi.busyFilled(
                        context,
                        ReferralStrings.get(context, "account.deleteConfirm"),
                        0,
                        ReferralUi.DANGER_FILL,
                        0xFFFFFFFF,
                        this::confirm);
        column.addView(
                mConfirmButton,
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 12)));
        return column;
    }

    /**
     * Un champ pour un code à six chiffres : chiffres seulement, centré, chasse fixe. ⚠️ La touche
     * « Terminé » du clavier le range — elle ne VALIDE rien : c'est le bouton qui valide.
     */
    static EditText codeField(Context context, ReferralUi.Palette p) {
        EditText field = new EditText(context);
        field.setBackground(ReferralUi.rounded(p.panel, ReferralUi.dp(context, 14)));
        int pad = ReferralUi.dp(context, 14);
        field.setPadding(pad, pad, pad, pad);
        field.setHint("123456");
        field.setHintTextColor(p.text3);
        field.setTextColor(p.text);
        field.setTextSize(22);
        field.setTypeface(Typeface.create(Typeface.MONOSPACE, Typeface.BOLD));
        field.setLetterSpacing(0.2f);
        field.setGravity(Gravity.CENTER);
        field.setSingleLine(true);
        field.setInputType(InputType.TYPE_CLASS_NUMBER);
        field.setFilters(new InputFilter[] {new InputFilter.LengthFilter(ReferralDeletion.codeLength)});
        field.setImeOptions(EditorInfo.IME_ACTION_DONE | EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        // Un code à usage unique n'est pas un mot de passe à retenir.
        field.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        // ⚠️ Toujours de gauche à droite : ce sont des chiffres, même en arabe.
        field.setTextDirection(View.TEXT_DIRECTION_LTR);
        field.setOnEditorActionListener(
                (v, actionId, event) -> {
                    if (actionId != EditorInfo.IME_ACTION_DONE) return false;
                    hideKeyboard(v);
                    return true;
                });
        return field;
    }

    static void hideKeyboard(View field) {
        field.clearFocus();
        InputMethodManager imm = field.getContext().getSystemService(InputMethodManager.class);
        if (imm != null) imm.hideSoftInputFromWindow(field.getWindowToken(), 0);
    }

    static void showKeyboard(View field) {
        field.post(
                () -> {
                    if (!field.isAttachedToWindow() || !field.requestFocus()) return;
                    InputMethodManager imm =
                            field.getContext().getSystemService(InputMethodManager.class);
                    if (imm != null) imm.showSoftInput(field, InputMethodManager.SHOW_IMPLICIT);
                });
    }

    /** Le cadre rouge des deux temps de la suppression : son titre, son contenu, l'erreur, « Annuler ». */
    private View danger(LinearLayout content, TextView problem) {
        Context context = getContext();
        LinearLayout box = box(ReferralUi.withAlpha(mDanger, 0.55f));
        box.addView(head());
        box.addView(
                content,
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 12)));
        box.addView(
                problem,
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 12)));
        mCancel = textLink(ReferralStrings.get(context, "account.cancel"), this::close);
        box.addView(mCancel, linkParams());
        return box;
    }

    private LinearLayout box(int stroke) {
        Context context = getContext();
        LinearLayout box = ReferralUi.column(context);
        int pad = ReferralUi.dp(context, 16);
        box.setPadding(pad, pad, pad, ReferralUi.dp(context, 8));
        box.setBackground(
                ReferralUi.rounded(0, ReferralUi.dp(context, 16), ReferralUi.dp(context, 1), stroke));
        return box;
    }

    private TextView head() {
        Context context = getContext();
        return ReferralUi.text(
                context,
                ReferralStrings.get(context, "account.delete"),
                17,
                ReferralUi.SEMIBOLD,
                mP.text);
    }

    private View textLink(String label, Runnable action) {
        Context context = getContext();
        TextView link = ReferralUi.text(context, label, 13, ReferralUi.SEMIBOLD, mP.text);
        link.setGravity(Gravity.CENTER);
        int padH = ReferralUi.dp(context, 14);
        link.setPadding(padH, 0, padH, 0);
        link.setMinHeight(ReferralUi.dp(context, 44));
        link.setBackground(
                ReferralUi.pressable(
                        null, ReferralUi.withAlpha(mP.text, 0.1f), ReferralUi.dp(context, 10)));
        link.setClickable(true);
        link.setFocusable(true);
        link.setOnClickListener(v -> action.run());
        return link;
    }

    private LinearLayout.LayoutParams linkParams() {
        LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
        params.gravity = Gravity.CENTER_HORIZONTAL;
        params.topMargin = ReferralUi.dp(getContext(), 4);
        return params;
    }

    /** L'état d'attente de CHAQUE bouton, et ce qui est permis pendant qu'un autre travaille. */
    private void update() {
        boolean idle = mWorking == null;
        if (mOpenLink != null && mOpenSpinner != null) {
            boolean checking = mWorking == Busy.CHECK;
            mOpenLink.setVisibility(checking ? INVISIBLE : VISIBLE);
            mOpenSpinner.setVisibility(checking ? VISIBLE : GONE);
            mOpenLink.setEnabled(idle);
        }
        if (mSendButton != null) {
            mSendButton.setBusy(mWorking == Busy.SEND);
            mSendButton.setAvailable(idle || mWorking == Busy.SEND);
        }
        if (mConfirmButton != null) {
            mConfirmButton.setBusy(mWorking == Busy.DELETE);
            mConfirmButton.setAvailable(mWorking == Busy.DELETE || (idle && enteredCode() != null));
        }
        if (mCodeField != null) mCodeField.setEnabled(idle);
        if (mCancel != null) {
            mCancel.setEnabled(idle);
            mCancel.setAlpha(idle ? 1f : 0.45f);
        }
    }

    private @Nullable String enteredCode() {
        return mCodeField == null
                ? null
                : ReferralDeletion.normalizeCode(mCodeField.getText().toString());
    }

    private void setProblem(@Nullable String message) {
        if (mProblem == null) return;
        mProblem.setText(message == null ? "" : message);
        mProblem.setVisibility(message == null ? GONE : VISIBLE);
    }

    private void setWorking(@Nullable Busy working) {
        mWorking = working;
        mHost.onDeletionBusy(working != null);
        update();
    }

    private void show(Step step) {
        mStep = step;
        build();
        if (step == Step.CODE && mCodeField != null) showKeyboard(mCodeField);
    }

    // -------------------- Les gestes --------------------

    /** « Supprimer mon compte dev&din » : la question se pose au serveur AVANT tout code. */
    void open() {
        if (mWorking != null) return;
        setProblem(null);
        setWorking(Busy.CHECK);
        mController.checkAccountDeletable(
                (ReferralDeletability verdict) -> {
                    setWorking(null);
                    switch (verdict.kind) {
                        case DELETABLE:
                            show(Step.WARNING);
                            break;
                        case BLOCKED:
                            mApps = new ArrayList<>(verdict.apps);
                            show(Step.BLOCKED);
                            break;
                        case UNREACHABLE:
                            // ⚠️ Sans réponse, on n'ouvre RIEN : pas de code envoyé sur un « on ne
                            // sait pas ».
                            fail("account.unreachable");
                            break;
                        case FAILED:
                        default:
                            fail("account.deleteFailed");
                            break;
                    }
                });
    }

    /** « Recevoir le code de confirmation ». */
    void askCode() {
        if (mWorking != null) return;
        setProblem(null);
        setWorking(Busy.SEND);
        mController.requestAccountDeletionCode(
                (ReferralDeletionCode sent) -> {
                    setWorking(null);
                    switch (sent.kind) {
                        case SENT:
                            mDestination = sent.destination == null ? "" : sent.destination;
                            show(Step.CODE);
                            break;
                        case UNREACHABLE:
                            fail("account.unreachable");
                            break;
                        case FAILED:
                        default:
                            fail("account.deleteSendFailed");
                            break;
                    }
                });
    }

    /** « Supprimer définitivement ». */
    private void confirm() {
        String digits = enteredCode();
        if (digits == null || mWorking != null) return;
        setProblem(null);
        if (mCodeField != null) hideKeyboard(mCodeField);
        setWorking(Busy.DELETE);
        ReferralUi.tick(this);
        mController.deleteConnectedAccount(
                digits,
                (ReferralDeletionOutcome outcome) -> {
                    setWorking(null);
                    switch (outcome.kind) {
                        case DELETED:
                            // ⚠️ Rien après : le compte parti, cette vue n'est plus à l'écran.
                            mHost.onAccountDeleted();
                            break;
                        case USED_ELSEWHERE:
                            // Le serveur garde le dernier mot : s'il refuse malgré la question
                            // posée à l'ouverture, on le dit de la même façon.
                            mApps = new ArrayList<>(outcome.apps);
                            show(Step.BLOCKED);
                            break;
                        case BAD_CODE:
                            if (mCodeField != null) {
                                mCodeField.setText("");
                                // Le clavier s'est rangé pour confirmer : il revient pour corriger.
                                showKeyboard(mCodeField);
                            }
                            fail("account.badCode");
                            break;
                        case UNREACHABLE:
                            fail("account.unreachable");
                            break;
                        case FAILED:
                        default:
                            fail("account.deleteFailed");
                            break;
                    }
                });
    }

    private void fail(String key) {
        ReferralUi.reject(this);
        setProblem(ReferralStrings.get(getContext(), key));
    }

    private void close() {
        if (mCodeField != null) hideKeyboard(mCodeField);
        mDestination = "";
        show(Step.CLOSED);
    }

    /** 🧪 L'aperçu à l'émulateur : poser une étape sans passer par le réseau. ⛔ Jamais ailleurs. */
    void showForPreview(String step) {
        if (!mController.isPreviewOnly()) return;
        if ("blocked".equals(step)) {
            mApps = new ArrayList<>();
            mApps.add("Darsunaa");
            show(Step.BLOCKED);
        } else if ("blocked_unknown".equals(step)) {
            mApps = new ArrayList<>();
            show(Step.BLOCKED);
        } else if ("warning".equals(step)) {
            show(Step.WARNING);
        } else if ("code".equals(step)) {
            mDestination = "k****@example.com";
            show(Step.CODE);
        }
    }
}
