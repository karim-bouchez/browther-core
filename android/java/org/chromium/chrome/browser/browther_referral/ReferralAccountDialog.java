/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.content.Intent;
import android.graphics.Rect;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.BrowtherReferralController.ConnectOutcome;
import org.chromium.chrome.browser.browther_referral.core.ReferralAccount;
import org.chromium.chrome.browser.browther_referral.core.ReferralAccountLabel;

/**
 * Le <b>compte dev&din FACULTATIF</b> sur Android — le contrat commun à toutes les apps
 * (docs/PARRAINAGE.md § 7.1, tableau « Le contrat ») ; port de {@code ReferralAccountPage} ({@code
 * ReferralAccountView.swift}, iOS : la référence). Règles pures : {@code core/ReferralAccount*},
 * {@code core/ReferralDeletion*}.
 *
 * <h2>Où il se trouve — ⛔ jamais derrière un défilement</h2>
 *
 * <ul>
 *   <li><b>L'en-tête de l'écran Parrainage</b> : une personne en face du retour, sur TOUS les
 *       onglets — grise, puis verte et cochée une fois connecté ({@link ReferralHomeDialog}).
 *       C'est par là qu'on voit avec quel compte on est connecté, qu'on se déconnecte, qu'on
 *       supprime, et qu'on RETROUVE un compte sur un appareil neuf, où l'on n'a rien en jeu par
 *       définition.
 *   <li><b>Les Paramètres</b> : la ligne « Mon compte », avec son état en clair ({@code
 *       ReferralAccountSettingsPreference}) — c'est elle qui porte le libellé que l'icône de
 *       l'en-tête n'a pas.
 * </ul>
 *
 * <h2>Comment il se NOMME (Karim, 2026-10-08 — private/docs/PARRAINAGE.md § 11.5)</h2>
 *
 * <p>⭐ <b>« Mon compte » aux points d'entrée</b>, et l'on dit « Connecte-toi ». ⛔ Pas « Compte
 * dev&din » : qui ne connaît pas le studio ne sait pas de quoi on lui parle. <b>dev&din se présente
 * DANS la page</b>, une fois entré ({@code account.about}, et la signature « Un projet dev&din »).
 * Le nom reste sur « Supprimer mon compte dev&din » : la suppression vaut pour toutes ses apps.
 * L'icône d'ENTRÉE est une personne ; le bouclier reste là où les mots disent « à l'abri » — en
 * tête de cette page, et sur les rangées des onglets.
 *
 * <h2>Où il se propose</h2>
 *
 * Dans l'onglet de ce qui est en jeu, avec SES mots : {@link ReferralAccountHint}. ⛔ Rien pour qui
 * est déjà connecté.
 *
 * <h2>Ce que la page montre</h2>
 *
 * <ul>
 *   <li><b>Non connecté</b> : pourquoi un compte (« mettre à l'abri » s'il y a quelque chose à
 *       perdre, « retrouver » sinon), puis les trois portes ({@link ReferralSignInView}). ⚠️ Pas de
 *       scanner de QR sur Android (relier un ordinateur) : hors périmètre de ce portage.
 *   <li><b>Connecté</b> : avec quel compte, « Déconnecter cet appareil », et la suppression en deux
 *       temps ({@link ReferralAccountDeletion}).
 *   <li>🔴 Dans les deux états : ce que le compte porte, et ce qu'il ne portera jamais.
 * </ul>
 *
 * <p>⚠️ À l'écran on dit « parrainage », ⛔ pas « soutien » : le mot se lisait « soutien
 * financier », et qui n'a rien payé ne s'y reconnaissait pas (recette Fajrunaa, 2026-10-07). Le
 * message de connexion NOMME ce qui suit.
 *
 * <p>⚠️ Elle n'est pas une fenêtre du flow : son ouverture s'écrit par {@code paywall_action {action:
 * account}} ({@code BrowtherReferralPresenter.openAccount}), ⛔ pas par {@code paywall_shown}.
 */
public final class ReferralAccountDialog extends Dialog
        implements BrowtherReferralController.Listener,
                ReferralSignInView.Host,
                ReferralAccountDeletion.Host {
    private static final long TOAST_MS = 6_000;

    private final Activity mActivity;
    private final ReferralUi.Palette mP;
    private final BrowtherReferralController mController = BrowtherReferralController.get();
    private final Handler mHandler = new Handler(Looper.getMainLooper());

    private @Nullable ScrollView mScroll;
    private @Nullable LinearLayout mColumn;
    /**
     * Ce qui est dessiné : connecté, ou non. ⚠️ Seul un CHANGEMENT d'état redessine la page ; le
     * reste (une adresse qui arrive, un statut qui se rafraîchit) se met à jour en place — ⛔ on
     * n'efface jamais une saisie en cours parce que le service a répondu.
     */
    private @Nullable Boolean mShownConnected;

    private @Nullable TextView mBody;
    private @Nullable ReferralSignInView mSignIn;
    private @Nullable TextView mConnectedLine;
    private @Nullable ReferralUi.BusyButton mSignOut;
    private @Nullable ReferralAccountDeletion mDeletion;

    public ReferralAccountDialog(Activity activity) {
        super(activity, android.R.style.Theme_DeviceDefault_DayNight);
        mActivity = activity;
        mP = ReferralUi.palette(activity);
    }

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        Context context = getContext();

        FrameLayout root = new FrameLayout(context);
        root.setBackgroundColor(mP.screen);
        root.setFitsSystemWindows(true);

        LinearLayout page = ReferralUi.column(context);
        // ⚠️ Android 9 (§ 12.38) : la barre porte le fond de l'écran — invisible, ⛔ ne pas retirer.
        FrameLayout bar = new FrameLayout(context);
        bar.setBackgroundColor(mP.screen);
        TextView title =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "account.title"),
                        17,
                        ReferralUi.SEMIBOLD,
                        mP.text);
        title.setGravity(Gravity.CENTER);
        title.setSingleLine(true);
        title.setEllipsize(TextUtils.TruncateAt.END);
        int barPad = ReferralUi.dp(context, 56);
        title.setPadding(barPad, 0, barPad, 0);
        bar.addView(title, ReferralUi.frame(ReferralUi.MATCH, ReferralUi.MATCH, Gravity.CENTER));
        // Le retour : on vient de l'écran Parrainage ou des Paramètres, et on y revient.
        ImageView back =
                ReferralUi.glyph(context, R.drawable.browther_intro_glyph_chevron_left, 18, mP.text2);
        back.getDrawable().mutate().setAutoMirrored(true);
        int backPad = ReferralUi.dp(context, 13);
        back.setPadding(backPad, backPad, backPad, backPad);
        back.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        back.setContentDescription(ReferralStrings.get(context, "invite.back"));
        back.setBackground(
                ReferralUi.pressable(
                        null, ReferralUi.withAlpha(mP.text, 0.1f), ReferralUi.dp(context, 22)));
        back.setOnClickListener(v -> handleBack());
        int backSize = ReferralUi.dp(context, 44);
        FrameLayout.LayoutParams backParams =
                ReferralUi.frame(backSize, backSize, Gravity.START | Gravity.CENTER_VERTICAL);
        backParams.setMarginStart(ReferralUi.dp(context, 6));
        bar.addView(back, backParams);
        page.addView(bar, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 52)));

        // Le contenu défile : ⚠️ le conteneur porte le fond de l'écran (§ 12.38).
        ScrollView scroll = new ScrollView(context);
        scroll.setBackgroundColor(mP.screen);
        scroll.setClipToPadding(false);
        FrameLayout holder = new FrameLayout(context);
        holder.setBackgroundColor(mP.screen);
        LinearLayout column = ReferralUi.column(context);
        column.setBackgroundColor(mP.screen);
        column.setPadding(0, ReferralUi.dp(context, 8), 0, ReferralUi.dp(context, 32));
        holder.addView(
                column,
                new FrameLayout.LayoutParams(
                        Math.min(
                                ReferralUi.dp(context, 560),
                                context.getResources().getDisplayMetrics().widthPixels),
                        ReferralUi.WRAP,
                        Gravity.CENTER_HORIZONTAL));
        scroll.addView(holder, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));
        page.addView(scroll, new LinearLayout.LayoutParams(ReferralUi.MATCH, 0, 1));
        mScroll = scroll;
        mColumn = column;

        root.addView(page, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        setContentView(root);

        Window window = getWindow();
        if (window != null) {
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
            window.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(mP.screen));
            window.setStatusBarColor(mP.screen);
            window.setNavigationBarColor(mP.screen);
            // Le clavier RÉTRÉCIT la fenêtre : le champ et son bouton restent au-dessus de lui.
            window.setSoftInputMode(
                    WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                            | WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowInsetsController insets = window.getInsetsController();
                if (insets != null) {
                    int light =
                            WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                                    | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                    insets.setSystemBarsAppearance(mP.dark ? 0 : light, light);
                }
            }
        }

        // 🔴 Chrome active le retour PRÉDICTIF : dès Android 13, le geste retour n'appelle plus
        // `onBackPressed` — sans ce rappel, il fermerait la page au lieu de refermer une étape.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getOnBackInvokedDispatcher()
                    .registerOnBackInvokedCallback(
                            android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::handleBack);
        }
        render();
    }

    @Override
    protected void onStart() {
        super.onStart();
        mController.addListener(this);
        mController.boot();
        BrowtherReferralPresenter.pageShown(this);
        render();
    }

    @Override
    protected void onStop() {
        super.onStop();
        mController.removeListener(this);
        BrowtherReferralPresenter.pageHidden(this);
        mHandler.removeCallbacksAndMessages(null);
        Window window = getWindow();
        if (window != null) ReferralToast.hideIfOn(window.getDecorView());
    }

    @Override
    public void onReferralChanged() {
        render();
    }

    /** Android 10 à 12 ; au-delà, c'est le rappel du retour prédictif (`onCreate`). */
    @Override
    @android.annotation.SuppressLint("GestureBackNavigation")
    public void onBackPressed() {
        handleBack();
    }

    /**
     * Le retour referme d'abord l'étape ouverte (la suppression, le code par e-mail), puis la page.
     * ⚠️ Pendant qu'une suppression ou une connexion est en route, il ne fait rien : on ne lâche pas
     * un appel dont on attend la réponse.
     */
    private void handleBack() {
        if (mDeletion != null && mDeletion.isOpen()) {
            mDeletion.closeIfIdle();
            return;
        }
        if (mSignIn != null && mSignIn.isOpen()) {
            mSignIn.backIfIdle();
            return;
        }
        dismiss();
    }

    // -------------------- Le dessin --------------------

    private void render() {
        LinearLayout column = mColumn;
        if (column == null) return;
        ReferralAccount account = mController.account();
        boolean connected = account != null;
        if (mShownConnected == null || mShownConnected != connected) {
            mShownConnected = connected;
            column.removeAllViews();
            mBody = null;
            mSignIn = null;
            mConnectedLine = null;
            mSignOut = null;
            mDeletion = null;
            if (account != null) {
                connected(column);
            } else {
                signedOut(column);
            }
            // 🔴 Ce que le compte porte, et ce qu'il ne portera jamais — dit tel quel, dans les
            // deux états.
            add(column, note(ReferralStrings.get(getContext(), "account.only")), 16);
            // ⭐ dev&din se présente ICI, dans la page — pas à ses portes (§ 11.5).
            add(column, note(ReferralStrings.get(getContext(), "account.about")), 22);
            add(
                    column,
                    ReferralUi.studioSignature(getContext(), mP, this::openStudioSite),
                    12,
                    ReferralUi.WRAP,
                    ReferralUi.WRAP);
        }
        if (account != null) {
            if (mConnectedLine != null) mConnectedLine.setText(connectedLine(getContext(), account));
        } else {
            if (mBody != null) mBody.setText(bodyText());
            if (mSignIn != null) mSignIn.setWebBusy(mController.webSignInExchanging());
        }
        // L'issue d'une connexion par l'onglet (Google, Apple) : c'est la page qui la dit.
        ConnectOutcome result = mController.takeWebSignInResult();
        if (result == ConnectOutcome.CONNECTED) {
            onConnected();
        } else if (result != null && mSignIn != null) {
            mSignIn.showWebFailure(result);
        }
    }

    private void signedOut(LinearLayout column) {
        Context context = getContext();
        ImageView shield =
                ReferralUi.glyph(context, R.drawable.browther_referral_glyph_shield, 26, mP.text);
        add(column, shield, 4, ReferralUi.dp(context, 26));
        // « Mettre à l'abri » ne se dit que s'il y a quelque chose à perdre ; qui arrive sur un
        // appareil neuf RETROUVE un compte.
        TextView body = ReferralUi.text(context, bodyText(), 16, ReferralUi.REGULAR, mP.text2);
        body.setLineSpacing(0, 1.12f);
        mBody = body;
        add(column, body, 10);

        ReferralSignInView signIn =
                new ReferralSignInView(
                        context, mActivity, mP, this, ReferralUi.dp(context, SIDE_DP));
        mSignIn = signIn;
        // ⚠️ Toute la largeur : le bloc rend lui-même les marges de la page à ses éléments (le
        // tampon « Recommandé » a besoin d'un peu de celle du bouton Google).
        LinearLayout.LayoutParams params = ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP);
        params.topMargin = ReferralUi.dp(context, 8);
        column.addView(signIn, params);

        // ⚠️ Le piège des deux comptes, dit là où l'on choisit sa porte.
        add(column, note(ReferralStrings.get(context, "account.sameWay")), 14);
    }

    private void connected(LinearLayout column) {
        Context context = getContext();
        ImageView shield =
                ReferralUi.glyph(
                        context, R.drawable.browther_referral_glyph_shield_check, 26, mP.green);
        add(column, shield, 4, ReferralUi.dp(context, 26));
        TextView line = ReferralUi.text(context, 20, ReferralUi.SEMIBOLD, mP.text);
        mConnectedLine = line;
        add(column, line, 10);
        TextView body =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "account.connectedBody"),
                        16,
                        ReferralUi.REGULAR,
                        mP.text2);
        body.setLineSpacing(0, 1.12f);
        add(column, body, 8);
        // ⚠️ « De la même façon » : Apple « masquer mon adresse » d'un côté et Google de l'autre
        // font DEUX comptes, et rien ne passe — le piège du § 7.1.
        add(column, note(ReferralStrings.get(context, "account.sameWay")), 16);

        ReferralUi.BusyButton signOut =
                ReferralUi.busyOutline(
                        context,
                        ReferralStrings.get(context, "account.signOutDevice"),
                        0,
                        mP.text2,
                        ReferralUi.withAlpha(mP.text2, 0.55f),
                        mController::signOut);
        mSignOut = signOut;
        add(column, signOut, 18);

        ReferralAccountDeletion deletion = new ReferralAccountDeletion(context, mP, this);
        mDeletion = deletion;
        add(column, deletion, 14);
    }

    private static final float SIDE_DP = 20;

    private void add(LinearLayout column, View view, float topDp) {
        add(column, view, topDp, ReferralUi.MATCH);
    }

    /** Un élément de la page, à ses marges : toute la largeur, ou un carré de {@code width}. */
    private void add(LinearLayout column, View view, float topDp, int width) {
        add(column, view, topDp, width, width == ReferralUi.MATCH ? ReferralUi.WRAP : width);
    }

    private void add(LinearLayout column, View view, float topDp, int width, int height) {
        Context context = getContext();
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(width, height);
        params.topMargin = ReferralUi.dp(context, topDp);
        params.setMarginStart(ReferralUi.dp(context, SIDE_DP));
        params.setMarginEnd(ReferralUi.dp(context, SIDE_DP));
        column.addView(view, params);
    }

    /** Une précision, en petit, alignée sur le début de la ligne. */
    private TextView note(String text) {
        TextView view = ReferralUi.text(getContext(), text, 13, ReferralUi.REGULAR, mP.text2);
        view.setLineSpacing(0, 1.1f);
        return view;
    }

    private String bodyText() {
        return ReferralStrings.get(
                getContext(),
                mController.accountStakes().hasSomethingToShelter()
                        ? "account.bodyShelter"
                        : "account.bodyRecover");
    }

    /**
     * Un compte Apple à adresse masquée se nomme « avec Apple », pas par son relais illisible
     * ({@link ReferralAccountLabel}).
     */
    static String connectedLine(Context context, ReferralAccount account) {
        ReferralAccountLabel label = ReferralAccountLabel.of(account);
        switch (label.kind) {
            case EMAIL:
                return ReferralStrings.fill(
                        ReferralStrings.get(context, "account.connectedAs"),
                        "email",
                        label.email == null ? "" : label.email);
            case APPLE:
                return ReferralStrings.get(context, "account.connectedApple");
            case UNKNOWN:
            default:
                return ReferralStrings.get(context, "account.connected");
        }
    }

    /**
     * La signature « Un projet dev&din » mène au site du studio — dans un onglet de Browther, que
     * cette page et l'écran Parrainage (plein écran) couvriraient : on les referme d'abord, comme
     * pour une connexion par onglet. ⛔ Aucun évènement.
     */
    private void openStudioSite() {
        Intent view = new Intent(Intent.ACTION_VIEW, Uri.parse("https://devndin.com"));
        BrowtherReferralPresenter.dismissPages();
        try {
            // ⚠️ Dans Browther lui-même : sans le paquet, Android proposerait un autre navigateur.
            mActivity.startActivity(new Intent(view).setPackage(mActivity.getPackageName()));
        } catch (RuntimeException e) {
            try {
                mActivity.startActivity(view);
            } catch (RuntimeException none) {
                // Rien pour ouvrir une adresse : on reste où l'on est.
            }
        }
    }

    /** Un mot de la page sur elle-même : ⚠️ ancré sur SA fenêtre, sinon il s'afficherait dessous. */
    private void toast(String text) {
        Window window = getWindow();
        if (window == null || !isShowing()) return;
        View decor = window.getDecorView();
        ReferralUi.success(decor);
        ReferralToast.showOn(decor, text, null, TOAST_MS);
    }

    // -------------------- Ce que la connexion et la suppression demandent à la page --------------------

    @Override
    public void onLeavingForWebSignIn() {
        // La personne part se connecter dans un onglet : cette page et l'écran Parrainage le
        // couvriraient. La page revient d'elle-même au retour (`finishWebSignIn`).
        BrowtherReferralPresenter.dismissPages();
    }

    @Override
    public void onConnected() {
        toast(mController.linkedMessage(getContext()));
    }

    @Override
    public void onDeletionBusy(boolean busy) {
        // ⛔ On ne se déconnecte pas pendant qu'une suppression est en route.
        if (mSignOut != null) mSignOut.setAvailable(!busy);
    }

    @Override
    public void onAccountDeleted() {
        toast(ReferralStrings.get(getContext(), "account.deleted"));
    }

    /**
     * Un champ a le focus : une fois le clavier monté, lui et le bouton qui le suit doivent être
     * visibles. ⚠️ Sur Android la fenêtre n'est pas toujours rétrécie à temps : on le redemande un
     * peu après.
     */
    @Override
    public void onFieldFocused(View field) {
        mHandler.postDelayed(
                () -> {
                    if (mScroll == null || !field.isAttachedToWindow()) return;
                    Rect area = new Rect(0, 0, field.getWidth(), field.getHeight());
                    // La place du bouton qui suit le champ.
                    area.bottom += ReferralUi.dp(getContext(), 96);
                    field.requestRectangleOnScreen(area, false);
                },
                320);
    }

    /** 🧪 L'aperçu à l'émulateur : poser une étape de la suppression sans réseau. ⛔ Jamais ailleurs. */
    public void showDeletionForPreview(String step) {
        if (mDeletion != null) mDeletion.showForPreview(step);
    }
}
