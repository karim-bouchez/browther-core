/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.animation.ObjectAnimator;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Typeface;
import android.text.Editable;
import android.text.InputFilter;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.RedeemOutcome;
import org.chromium.chrome.browser.browther_referral.core.RedeemRefusal;
import org.chromium.chrome.browser.browther_referral.core.ReferralCode;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;

/**
 * L'écran O — le code d'un proche, et RIEN d'autre (§ 12.24) : port de {@code
 * ReferralWelcomeContent} + {@code ReferralRedeemField} (iOS). ⛔ Pas de partie « inviter » : la
 * personne ne connaît pas encore l'app. ⭐ La même rédaction sert l'introduction, l'onglet « Code
 * reçu » de l'écran Parrainage (sans parrain) et l'aperçu de recette — ⛔ jamais deux textes.
 *
 * <ul>
 *   <li>🔴 « J'ai un code de parrainage » est AMBIGU : le titre dit « Un proche t'a parlé de
 *       Browther ? ».
 *   <li>Un vrai champ, et le bouton unique vit DANS le champ (Coller → Valider), en pastille à son
 *       bout — ⛔ pas posé à côté : il mangeait la largeur.
 *   <li>La forme se vérifie avant le service ({@link ReferralCode#readInput}) : « TEST » dit « un
 *       code fait 6 caractères ». Un lien collé est accepté en silence.
 *   <li>Chasse fixe seulement pour le code tapé : le texte d'attente est une phrase.
 *   <li>Un refus secoue le champ (haptique de refus) ; une réussite se fête (l'appelant tire les
 *       confettis, {@code onRedeemed}). Mouvement réduit : ni secousse.
 * </ul>
 */
public class ReferralCodeEntry extends LinearLayout {
    private final String mSource;
    private final boolean mPreview;
    private final @Nullable Runnable mOnRedeemed;
    private final ReferralUi.Palette mP;

    private final FrameLayout mBadge;
    private final LinearLayout mFieldBlock;
    private final LinearLayout mField;
    private final EditText mInput;
    private final TextView mPaste;
    private final TextView mValidate;
    private final ProgressBar mBusy;
    private final TextView mError;
    private final LinearLayout mDoneLine;
    private boolean mRedeemed;
    private boolean mBusyNow;

    public ReferralCodeEntry(
            Context context, String source, boolean preview, @Nullable Runnable onRedeemed) {
        super(context);
        mSource = source;
        mPreview = preview;
        mOnRedeemed = onRedeemed;
        mP = ReferralUi.palette(context);
        ReferralUi.Palette p = mP;
        setOrientation(VERTICAL);
        setGravity(Gravity.CENTER_HORIZONTAL);

        TextView head = ReferralUi.title(context, p, ReferralStrings.get(context, "redeem.head"));
        addView(head, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        TextView body = ReferralUi.body(context, p, ReferralStrings.get(context, "redeem.body"));
        addView(body, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 8)));

        // Le disque qui « s'ouvre ».
        mBadge = new FrameLayout(context);
        int badge = ReferralUi.dp(context, 96);
        LinearLayout.LayoutParams badgeParams = new LinearLayout.LayoutParams(badge, badge);
        badgeParams.gravity = Gravity.CENTER_HORIZONTAL;
        badgeParams.topMargin = ReferralUi.dp(context, 28);
        addView(mBadge, badgeParams);

        // Le champ.
        mFieldBlock = ReferralUi.column(context);
        mField = ReferralUi.row(context);
        mField.setPadding(ReferralUi.dp(context, 16), 0, ReferralUi.dp(context, 6), 0);
        mInput = new EditText(context);
        mInput.setBackground(null);
        mInput.setHint(ReferralStrings.get(context, "redeem.placeholder"));
        mInput.setHintTextColor(p.text3);
        mInput.setTextColor(p.text);
        mInput.setSingleLine(true);
        mInput.setInputType(
                InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
                        | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                        | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD);
        mInput.setImeOptions(EditorInfo.IME_ACTION_DONE);
        mInput.setFilters(new InputFilter[] {new InputFilter.AllCaps(), new InputFilter.LengthFilter(200)});
        mInput.setOnEditorActionListener(
                (v, actionId, event) -> {
                    if (actionId == EditorInfo.IME_ACTION_DONE
                            || (event != null && event.getKeyCode() == KeyEvent.KEYCODE_ENTER)) {
                        validate();
                        return true;
                    }
                    return false;
                });
        mInput.addTextChangedListener(
                new TextWatcher() {
                    @Override
                    public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

                    @Override
                    public void onTextChanged(CharSequence s, int start, int before, int count) {}

                    @Override
                    public void afterTextChanged(Editable s) {
                        setError(null);
                        styleInput();
                        updateTrailing();
                    }
                });
        mField.addView(mInput, new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1));

        mPaste = pill(context, ReferralStrings.get(context, "redeem.paste"), false);
        mPaste.setOnClickListener(v -> paste());
        mField.addView(mPaste, pillParams(context));
        mValidate = pill(context, ReferralStrings.get(context, "redeem.validate"), true);
        mValidate.setOnClickListener(v -> validate());
        mField.addView(mValidate, pillParams(context));
        mBusy = new ProgressBar(context);
        mBusy.setIndeterminate(true);
        int busy = ReferralUi.dp(context, 24);
        LinearLayout.LayoutParams busyParams = new LinearLayout.LayoutParams(busy, busy);
        busyParams.setMarginStart(ReferralUi.dp(context, 10));
        busyParams.setMarginEnd(ReferralUi.dp(context, 10));
        mField.addView(mBusy, busyParams);
        mFieldBlock.addView(mField, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 54)));

        mError = ReferralUi.text(context, 13, ReferralUi.REGULAR, 0xFFD32F2F);
        mError.setGravity(Gravity.CENTER_HORIZONTAL);
        mError.setTextAlignment(TEXT_ALIGNMENT_CENTER);
        mError.setVisibility(GONE);
        mFieldBlock.addView(mError, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 8)));
        addView(mFieldBlock, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 28)));

        // La réussite (ou le code déjà utilisé).
        mDoneLine = ReferralUi.row(context);
        mDoneLine.setGravity(Gravity.CENTER);
        ImageView check = ReferralUi.glyph(context, R.drawable.browther_intro_glyph_check, 16, p.green);
        mDoneLine.addView(check);
        TextView doneText =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "redeem.validatedLine"),
                        15,
                        ReferralUi.MEDIUM,
                        p.green);
        doneText.setGravity(Gravity.CENTER);
        doneText.setTextAlignment(TEXT_ALIGNMENT_CENTER);
        LinearLayout.LayoutParams doneParams = new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1);
        doneParams.setMarginStart(ReferralUi.dp(context, 6));
        mDoneLine.addView(doneText, doneParams);
        addView(mDoneLine, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 28)));

        styleInput();
        render();
    }

    /** Dans l'introduction : le visuel s'efface quand le clavier monte (le champ reste visible). */
    public void setBadgeVisible(boolean visible) {
        mBadge.setVisibility(visible ? VISIBLE : GONE);
    }

    private boolean alreadyReferred() {
        ReferralStatus status = BrowtherReferralController.get().known();
        return status != null && status.referredBy != null;
    }

    private void render() {
        boolean done = mRedeemed || alreadyReferred();
        Context context = getContext();
        mBadge.removeAllViews();
        mBadge.setBackground(ReferralUi.oval(done ? mP.greenFill : mP.goldSurface));
        ImageView icon =
                ReferralUi.glyph(
                        context,
                        done ? R.drawable.browther_intro_glyph_check : R.drawable.browther_referral_glyph_gift,
                        40,
                        done ? 0xFFFFFFFF : mP.gold);
        int size = ReferralUi.dp(context, 40);
        mBadge.addView(icon, ReferralUi.frame(size, size, Gravity.CENTER));
        mFieldBlock.setVisibility(done ? GONE : VISIBLE);
        mDoneLine.setVisibility(done ? VISIBLE : GONE);
        mField.setBackground(
                ReferralUi.rounded(
                        mP.panel,
                        ReferralUi.dp(context, 16),
                        ReferralUi.dp(context, 1.5f),
                        mError.getVisibility() == VISIBLE ? 0x99E53935 : 0x00000000));
        updateTrailing();
    }

    private void updateTrailing() {
        boolean empty = mInput.getText().length() == 0;
        mBusy.setVisibility(mBusyNow ? VISIBLE : GONE);
        mPaste.setVisibility(!mBusyNow && empty ? VISIBLE : GONE);
        mValidate.setVisibility(!mBusyNow && !empty ? VISIBLE : GONE);
    }

    /** Chasse fixe seulement pour le code tapé : le texte d'attente est une phrase. */
    private void styleInput() {
        boolean empty = mInput.getText().length() == 0;
        if (empty) {
            mInput.setTypeface(ReferralUi.typeface(ReferralUi.REGULAR));
            mInput.setTextSize(16);
            mInput.setLetterSpacing(0);
        } else {
            mInput.setTypeface(Typeface.create(Typeface.MONOSPACE, Typeface.BOLD));
            mInput.setTextSize(20);
            mInput.setLetterSpacing(0.15f);
        }
    }

    private void paste() {
        ClipboardManager clipboard =
                (ClipboardManager) getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard == null || !clipboard.hasPrimaryClip()) return;
        ClipData clip = clipboard.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return;
        CharSequence text = clip.getItemAt(0).coerceToText(getContext());
        if (text == null) return;
        mInput.setText(text.toString().trim());
        mInput.setSelection(mInput.getText().length());
        validate();
    }

    private void validate() {
        Context context = getContext();
        ReferralCode.Input input = ReferralCode.readInput(mInput.getText().toString());
        if (!input.isSuccess()) {
            switch (input.error) {
                case LENGTH:
                    refuse(ReferralStrings.get(context, "redeem.inputError.length"));
                    return;
                case ALPHABET:
                    refuse(ReferralStrings.get(context, "redeem.inputError.alphabet"));
                    return;
                case EMPTY:
                default:
                    return;
            }
        }
        if (mPreview) {
            // ⛔ Un aperçu n'écrit rien : la forme est vérifiée, le service n'est pas appelé.
            succeed();
            return;
        }
        mBusyNow = true;
        updateTrailing();
        BrowtherReferralController.get()
                .redeem(
                        input.code,
                        mSource,
                        (RedeemOutcome outcome) -> {
                            mBusyNow = false;
                            updateTrailing();
                            if (outcome == null) {
                                refuse(ReferralStrings.get(context, "redeem.refusal.unavailable"));
                            } else if (outcome.accepted) {
                                succeed();
                            } else {
                                refuse(message(context, outcome.refusal));
                            }
                        });
    }

    private void succeed() {
        hideKeyboard();
        ReferralUi.success(this);
        mRedeemed = true;
        render();
        if (!ReferralUi.reduceMotion(getContext())) {
            mBadge.setScaleX(0.85f);
            mBadge.setScaleY(0.85f);
            mBadge.animate().scaleX(1f).scaleY(1f).setDuration(420)
                    .setInterpolator(new android.view.animation.OvershootInterpolator(2.2f)).start();
        }
        if (mOnRedeemed != null) mOnRedeemed.run();
    }

    private void refuse(String message) {
        setError(message);
        ReferralUi.reject(this);
        if (ReferralUi.reduceMotion(getContext())) return;
        // La secousse d'un refus : trois allers-retours qui s'amortissent.
        float travel = ReferralUi.dp(getContext(), 8);
        ObjectAnimator shake =
                ObjectAnimator.ofFloat(
                        mField, "translationX",
                        0, travel, -travel * 0.8f, travel * 0.6f, -travel * 0.4f, travel * 0.2f, 0);
        shake.setDuration(400);
        shake.start();
    }

    private void setError(@Nullable String message) {
        boolean had = mError.getVisibility() == VISIBLE;
        mError.setText(message == null ? "" : message);
        mError.setVisibility(message == null ? GONE : VISIBLE);
        if (had != (message != null)) render();
    }

    static String message(Context context, @Nullable RedeemRefusal reason) {
        if (reason == null) return ReferralStrings.get(context, "redeem.refusal.unknown_code");
        return ReferralStrings.get(context, "redeem.refusal." + reason.rawValue);
    }

    private void hideKeyboard() {
        mInput.clearFocus();
        InputMethodManager imm =
                (InputMethodManager) getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
        if (imm != null) imm.hideSoftInputFromWindow(mInput.getWindowToken(), 0);
    }

    private TextView pill(Context context, String label, boolean filled) {
        TextView pill =
                ReferralUi.text(
                        context, label, 14, ReferralUi.SEMIBOLD, filled ? mP.onPrimary : mP.text);
        int padH = ReferralUi.dp(context, 16);
        pill.setPadding(padH, 0, padH, 0);
        pill.setGravity(Gravity.CENTER);
        float radius = ReferralUi.dp(context, 100);
        pill.setBackground(
                ReferralUi.pressable(
                        filled
                                ? ReferralUi.rounded(mP.primary, radius)
                                : ReferralUi.rounded(0, radius, ReferralUi.dp(context, 1.5f), mP.text),
                        ReferralUi.withAlpha(mP.text, 0.15f),
                        radius));
        pill.setClickable(true);
        pill.setFocusable(true);
        return pill;
    }

    private static LinearLayout.LayoutParams pillParams(Context context) {
        return new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.dp(context, 40));
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        mField.animate().cancel();
    }
}
