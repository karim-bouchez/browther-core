/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.content.Context;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.BrowtherReferralController.ConnectOutcome;
import org.chromium.chrome.browser.browther_referral.core.ReferralAuthClient;
import org.chromium.chrome.browser.browther_referral.core.ReferralDeletion;

import java.util.Locale;

/**
 * La connexion elle-même : <b>trois portes</b> — Google, Apple, ou un code reçu par e-mail. Port de
 * {@code ReferralSignInSheet} ({@code ReferralAccountView.swift}) ; sur Android ce n'est pas une
 * feuille mais un bloc DE la page du compte (il n'y a pas de scanner de QR à lui passer devant).
 *
 * <ul>
 *   <li>⭐ <b>Google en tête, avec « Recommandé »</b> (docs/AUTH.md § « Quel SSO mettre en avant ») :
 *       une adresse réelle et vérifiée, sur tous les systèmes. Bouton PLEIN, et le tampon sur son
 *       coin ({@link ReferralStamp}). Apple ensuite, puis le code par e-mail.
 *   <li>Google et Apple ouvrent un onglet du navigateur ({@code BrowtherReferralController.signIn})
 *       : la page se ferme pour le laisser voir, et revient d'elle-même au retour.
 *   <li>🔴 Le code par e-mail ne dépend de RIEN de tout ça : adresse → code à six chiffres, sans
 *       quitter la fenêtre. Le sixième chiffre connecte (⚠️ au contraire de la suppression, qui se
 *       confirme d'un bouton).
 * </ul>
 */
public final class ReferralSignInView extends LinearLayout {
    /** Ce que la page du compte fait pour la connexion. */
    public interface Host {
        /** La personne part se connecter dans un onglet : les fenêtres du parrainage le couvrent. */
        void onLeavingForWebSignIn();

        /** Connecté : la page le dit (ce bloc n'est déjà plus à l'écran). */
        void onConnected();

        /** Un champ a le focus : la page le fait monter au-dessus du clavier. */
        void onFieldFocused(View field);
    }

    private enum Step {
        CHOOSE,
        EMAIL,
        CODE
    }

    /** ⚠️ Un état d'attente PAR bouton. */
    private enum Busy {
        GOOGLE,
        APPLE,
        SEND,
        VERIFY
    }

    private final Activity mActivity;
    private final ReferralUi.Palette mP;
    private final Host mHost;
    private final int mSide;
    private final BrowtherReferralController mController = BrowtherReferralController.get();

    private Step mStep = Step.CHOOSE;
    private @Nullable Busy mWorking;
    /**
     * L'onglet de connexion est revenu : le code s'échange, le compte se rattache — la roue est sur
     * le bouton du fournisseur choisi. {@code null} le reste du temps.
     */
    private @Nullable ReferralAuthClient.Provider mWebBusy;
    private String mAddress = "";

    private @Nullable ReferralUi.BusyButton mGoogle;
    private @Nullable ReferralUi.BusyButton mApple;
    private @Nullable ReferralUi.BusyButton mEmail;
    private @Nullable ReferralUi.BusyButton mSend;
    private @Nullable ReferralUi.BusyButton mVerify;
    private @Nullable EditText mEmailField;
    private @Nullable EditText mCodeField;
    private @Nullable View mBack;
    private @Nullable TextView mProblem;

    /**
     * @param context le contexte de la page (celui de sa fenêtre).
     * @param activity l'activité qui porte la page : c'est d'elle que part l'onglet de connexion.
     * @param sideMarginPx la marge de côté de la page : ce bloc prend toute la largeur et la rend à
     *     chacun de ses éléments — sauf l'enveloppe du bouton Google, qui en garde un peu pour le
     *     tampon.
     */
    public ReferralSignInView(
            Context context,
            Activity activity,
            ReferralUi.Palette palette,
            Host host,
            int sideMarginPx) {
        super(context);
        mActivity = activity;
        mP = palette;
        mHost = host;
        mSide = sideMarginPx;
        setOrientation(VERTICAL);
        build();
    }

    /**
     * L'onglet de connexion est revenu, le code s'échange : les portes attendent, la roue sur celle
     * qu'on a prise. {@code null} = plus rien n'est en route.
     */
    public void setWebBusy(@Nullable ReferralAuthClient.Provider provider) {
        if (mWebBusy == provider) return;
        mWebBusy = provider;
        if (provider != null && mStep != Step.CHOOSE) {
            // Le retour d'un onglet ramène toujours aux portes : c'est là qu'est la roue.
            mStep = Step.CHOOSE;
            build();
            return;
        }
        update();
    }

    /** L'issue d'une connexion par l'onglet qui n'a pas abouti. */
    public void showWebFailure(ConnectOutcome outcome) {
        setProblem(message(outcome));
    }

    /** Une étape à refermer avant de quitter la page ? (le geste retour) */
    public boolean isOpen() {
        return mStep != Step.CHOOSE;
    }

    /** Revient aux trois portes — {@code false} si un appel est en route. */
    public boolean backIfIdle() {
        if (mWorking != null) return false;
        back();
        return true;
    }

    // -------------------- Le dessin --------------------

    private void build() {
        Context context = getContext();
        removeAllViews();
        mGoogle = null;
        mApple = null;
        mEmail = null;
        mSend = null;
        mVerify = null;
        mEmailField = null;
        mCodeField = null;
        mBack = null;
        switch (mStep) {
            case EMAIL:
                emailStep();
                break;
            case CODE:
                codeStep();
                break;
            case CHOOSE:
            default:
                choose();
                break;
        }
        TextView problem = ReferralUi.text(context, 13, ReferralUi.REGULAR, ReferralUi.danger(mP));
        problem.setVisibility(GONE);
        mProblem = problem;
        add(problem, 12);
        update();
    }

    /** Un élément du bloc, aux marges de la page. */
    private void add(View view, float topDp) {
        LinearLayout.LayoutParams params =
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(getContext(), topDp));
        params.leftMargin = mSide;
        params.rightMargin = mSide;
        addView(view, params);
    }

    private void choose() {
        Context context = getContext();
        String withGoogle = ReferralStrings.get(context, "account.withGoogle");
        String recommended = ReferralStrings.get(context, "account.recommended");
        ReferralUi.BusyButton google =
                ReferralUi.busyFilled(
                        context,
                        withGoogle,
                        R.drawable.browther_referral_glyph_globe,
                        mP.primary,
                        mP.onPrimary,
                        () -> web(ReferralAuthClient.Provider.GOOGLE, Busy.GOOGLE));
        google.setContentDescription(withGoogle + " · " + recommended);
        mGoogle = google;
        // ⭐ Le tampon : sur le coin, HORS mise en page — l'enveloppe lui réserve sa place, le
        // bouton garde la largeur des deux autres.
        View envelope = ReferralStamp.wrap(context, mP, google, recommended);
        LinearLayout.LayoutParams envelopeParams =
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP);
        int room = ReferralStamp.sideRoom(context);
        envelopeParams.leftMargin = Math.max(0, mSide - room);
        envelopeParams.rightMargin = Math.max(0, mSide - room);
        addView(envelope, envelopeParams);

        int stroke = ReferralUi.withAlpha(mP.text2, 0.55f);
        mApple =
                ReferralUi.busyOutline(
                        context,
                        ReferralStrings.get(context, "account.withApple"),
                        R.drawable.browther_referral_glyph_apple,
                        mP.text,
                        stroke,
                        () -> web(ReferralAuthClient.Provider.APPLE, Busy.APPLE));
        add(mApple, 10);
        mEmail =
                ReferralUi.busyOutline(
                        context,
                        ReferralStrings.get(context, "account.withEmail"),
                        R.drawable.browther_referral_glyph_envelope,
                        mP.text,
                        stroke,
                        () -> {
                            setProblem(null);
                            show(Step.EMAIL);
                        });
        add(mEmail, 10);
    }

    private void emailStep() {
        Context context = getContext();
        EditText field = new EditText(context);
        field.setBackground(ReferralUi.rounded(mP.panel, ReferralUi.dp(context, 14)));
        int pad = ReferralUi.dp(context, 14);
        field.setPadding(pad, pad, pad, pad);
        field.setHint(ReferralStrings.get(context, "account.emailPlaceholder"));
        field.setHintTextColor(mP.text3);
        field.setTextColor(mP.text);
        field.setTextSize(16);
        field.setSingleLine(true);
        field.setInputType(
                InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                        | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        field.setImeOptions(EditorInfo.IME_ACTION_SEND | EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        field.setAutofillHints(View.AUTOFILL_HINT_EMAIL_ADDRESS);
        // ⚠️ Une adresse s'écrit de gauche à droite, même en arabe.
        field.setTextDirection(View.TEXT_DIRECTION_LTR);
        field.setTextAlignment(View.TEXT_ALIGNMENT_VIEW_START);
        field.setText(mAddress);
        field.setSelection(field.getText().length());
        field.setOnEditorActionListener(
                (v, actionId, event) -> {
                    if (actionId == EditorInfo.IME_ACTION_SEND
                            || (event != null
                                    && event.getAction() == KeyEvent.ACTION_DOWN
                                    && event.getKeyCode() == KeyEvent.KEYCODE_ENTER)) {
                        sendCode();
                        return true;
                    }
                    return false;
                });
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
        mEmailField = field;
        add(field, 0);
        mSend =
                ReferralUi.busyFilled(
                        context,
                        ReferralStrings.get(context, "account.sendCode"),
                        0,
                        mP.primary,
                        mP.onPrimary,
                        this::sendCode);
        add(mSend, 14);
        addBack();
    }

    private void codeStep() {
        Context context = getContext();
        TextView sent =
                ReferralUi.text(
                        context,
                        ReferralStrings.fill(
                                ReferralStrings.get(context, "account.codeSent"), "email", mAddress),
                        15,
                        ReferralUi.REGULAR,
                        mP.text);
        add(sent, 0);
        EditText field = ReferralAccountDeletion.codeField(context, mP);
        field.addTextChangedListener(
                new TextWatcher() {
                    @Override
                    public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

                    @Override
                    public void onTextChanged(CharSequence s, int start, int before, int count) {}

                    @Override
                    public void afterTextChanged(Editable s) {
                        update();
                        // Le sixième chiffre connecte, comme sur iOS : se connecter n'a rien
                        // d'irréversible.
                        if (enteredCode() != null) verify();
                    }
                });
        field.setOnFocusChangeListener(
                (v, focused) -> {
                    if (focused) mHost.onFieldFocused(v);
                });
        mCodeField = field;
        add(field, 14);
        mVerify =
                ReferralUi.busyFilled(
                        context,
                        ReferralStrings.get(context, "account.verify"),
                        0,
                        mP.primary,
                        mP.onPrimary,
                        this::verify);
        add(mVerify, 14);
        addBack();
    }

    /** « Recommencer » : revenir aux trois portes. */
    private void addBack() {
        Context context = getContext();
        TextView link =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "account.retry"),
                        13,
                        ReferralUi.SEMIBOLD,
                        mP.text);
        link.setGravity(Gravity.CENTER);
        int padH = ReferralUi.dp(context, 14);
        link.setPadding(padH, 0, padH, 0);
        link.setMinHeight(ReferralUi.dp(context, 44));
        link.setBackground(
                ReferralUi.pressable(
                        null, ReferralUi.withAlpha(mP.text, 0.1f), ReferralUi.dp(context, 10)));
        link.setClickable(true);
        link.setFocusable(true);
        link.setOnClickListener(v -> back());
        mBack = link;
        LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
        params.gravity = Gravity.CENTER_HORIZONTAL;
        params.topMargin = ReferralUi.dp(context, 6);
        addView(link, params);
    }

    /** L'état d'attente de CHAQUE bouton, et ce qui est permis pendant qu'un autre travaille. */
    private void update() {
        boolean idle = mWorking == null && mWebBusy == null;
        if (mGoogle != null) {
            boolean busy =
                    mWorking == Busy.GOOGLE || mWebBusy == ReferralAuthClient.Provider.GOOGLE;
            mGoogle.setBusy(busy);
            mGoogle.setAvailable(idle || busy);
        }
        if (mApple != null) {
            boolean busy = mWorking == Busy.APPLE || mWebBusy == ReferralAuthClient.Provider.APPLE;
            mApple.setBusy(busy);
            mApple.setAvailable(idle || busy);
        }
        if (mEmail != null) mEmail.setAvailable(idle);
        if (mSend != null) {
            mSend.setBusy(mWorking == Busy.SEND);
            mSend.setAvailable(mWorking == Busy.SEND || (idle && looksLikeEmail(typedAddress())));
        }
        if (mVerify != null) {
            mVerify.setBusy(mWorking == Busy.VERIFY);
            mVerify.setAvailable(mWorking == Busy.VERIFY || (idle && enteredCode() != null));
        }
        if (mEmailField != null) mEmailField.setEnabled(idle);
        if (mCodeField != null) mCodeField.setEnabled(idle);
        if (mBack != null) {
            mBack.setEnabled(idle);
            mBack.setAlpha(idle ? 1f : 0.45f);
        }
    }

    private String typedAddress() {
        return mEmailField == null
                ? mAddress
                : mEmailField.getText().toString().trim().toLowerCase(Locale.ROOT);
    }

    private @Nullable String enteredCode() {
        return mCodeField == null
                ? null
                : ReferralDeletion.normalizeCode(mCodeField.getText().toString());
    }

    /** Une adresse plausible : quelque chose, un « @ », un point après — c'est le serveur qui juge. */
    static boolean looksLikeEmail(String value) {
        String trimmed = value.trim();
        int at = trimmed.indexOf('@');
        return at > 0 && trimmed.indexOf('.', at) >= 0 && trimmed.indexOf(' ') < 0;
    }

    private void setProblem(@Nullable String message) {
        if (mProblem == null) return;
        mProblem.setText(message == null ? "" : message);
        mProblem.setVisibility(message == null ? GONE : VISIBLE);
    }

    private void show(Step step) {
        mStep = step;
        build();
        EditText field = step == Step.EMAIL ? mEmailField : step == Step.CODE ? mCodeField : null;
        if (field != null) ReferralAccountDeletion.showKeyboard(field);
    }

    private void back() {
        if (mEmailField != null) ReferralAccountDeletion.hideKeyboard(mEmailField);
        if (mCodeField != null) ReferralAccountDeletion.hideKeyboard(mCodeField);
        show(Step.CHOOSE);
    }

    // -------------------- Les gestes --------------------

    /** Google ou Apple : la page de connexion dev&din dans un onglet du navigateur. */
    private void web(ReferralAuthClient.Provider provider, Busy button) {
        if (mWorking != null || mWebBusy != null) return;
        setProblem(null);
        mWorking = button;
        update();
        if (mController.signIn(provider, mActivity)) {
            // ⚠️ La page et l'écran Parrainage sont des fenêtres plein écran : elles COUVRENT
            // l'onglet. Elles se ferment ; la page du compte revient au retour de la connexion.
            mHost.onLeavingForWebSignIn();
            return;
        }
        mWorking = null;
        update();
        fail(ReferralStrings.get(getContext(), "account.error"));
    }

    private void sendCode() {
        String address = typedAddress();
        if (!looksLikeEmail(address) || mWorking != null || mWebBusy != null) return;
        setProblem(null);
        mWorking = Busy.SEND;
        update();
        mController.sendEmailCode(
                address,
                (ConnectOutcome failure) -> {
                    mWorking = null;
                    update();
                    if (failure != null) {
                        fail(message(failure));
                        return;
                    }
                    mAddress = address;
                    show(Step.CODE);
                });
    }

    private void verify() {
        String code = enteredCode();
        if (code == null || mWorking != null || mWebBusy != null) return;
        setProblem(null);
        mWorking = Busy.VERIFY;
        update();
        mController.verifyEmailCode(
                mAddress,
                code,
                (ConnectOutcome outcome) -> {
                    mWorking = null;
                    update();
                    switch (outcome) {
                        case CONNECTED:
                            // ⚠️ Rien après : connecté, ce bloc n'est plus à l'écran.
                            mHost.onConnected();
                            break;
                        case BAD_CODE:
                            if (mCodeField != null) {
                                mCodeField.setText("");
                                // Le champ s'est éteint (et le clavier rangé) le temps de
                                // vérifier : il revient pour corriger.
                                ReferralAccountDeletion.showKeyboard(mCodeField);
                            }
                            fail(message(outcome));
                            break;
                        case UNREACHABLE:
                        case FAILED:
                        default:
                            fail(message(outcome));
                            break;
                    }
                });
    }

    private void fail(@Nullable String message) {
        ReferralUi.reject(this);
        setProblem(message);
    }

    private @Nullable String message(ConnectOutcome outcome) {
        Context context = getContext();
        switch (outcome) {
            case BAD_CODE:
                return ReferralStrings.get(context, "account.badCode");
            case UNREACHABLE:
                return ReferralStrings.get(context, "account.unreachable");
            case FAILED:
                return ReferralStrings.get(context, "account.error");
            case CONNECTED:
            default:
                return null;
        }
    }
}
