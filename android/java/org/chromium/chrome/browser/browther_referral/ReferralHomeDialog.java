/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.app.role.RoleManager;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
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
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.AccessState;
import org.chromium.chrome.browser.browther_referral.core.CoverageLabel;
import org.chromium.chrome.browser.browther_referral.core.ExtrasState;
import org.chromium.chrome.browser.browther_referral.core.InvitationItem;
import org.chromium.chrome.browser.browther_referral.core.InvitationStatus;
import org.chromium.chrome.browser.browther_referral.core.MilestoneBonus;
import org.chromium.chrome.browser.browther_referral.core.MilestoneScale;
import org.chromium.chrome.browser.browther_referral.core.ReferralAccountStake;
import org.chromium.chrome.browser.browther_referral.core.ReferralAccountStakes;
import org.chromium.chrome.browser.browther_referral.core.ReferralDate;
import org.chromium.chrome.browser.browther_referral.core.ReferralInvitations;
import org.chromium.chrome.browser.browther_referral.core.ReferralPricing;
import org.chromium.chrome.browser.browther_referral.core.ReferralProduct;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;
import org.chromium.chrome.browser.browther_referral.core.ValidationProgress;

import java.time.Instant;
import java.util.List;

/**
 * Écran 6 — <b>Parrainage</b> (docs/PARRAINAGE.md § 3, § 12.2, § 12.24, § 12.26) : port de {@code
 * ReferralHomeView.swift}. Une vraie PAGE, ouverte depuis le menu ⋯, les Paramètres, le rappel du
 * panneau Sawtunaa, et tout « Inviter un proche » du flow hors du circuit des trois façons (§
 * 12.15).
 *
 * <h2>🔴 En ONGLETS (§ 12.26)</h2>
 *
 * <p>Une page qui défile cache ce qui est en bas à qui ne défile pas ; des onglets se VOIENT. Un
 * contrôle segmenté EN HAUT, icône au-dessus du libellé : Inviter · Invitations · Code reçu ·
 * Soutenir (sur Android, la porte factice du paiement, § 12.27, rend « Soutenir » toujours
 * présent). ⛔ Pas de glissé entre onglets (la jauge se tire de côté) ; un cran d'haptique au
 * changement. ⭐ Le titre est celui de l'onglet ; un onglet peu rempli se CENTRE.
 *
 * <p>⚠️ Intitulés au genre neutre (§ 6) : ⛔ jamais « parrain » / « filleul ». ⚠️ Le bouton dit
 * « Partager mon code », ⛔ pas « Inviter un proche » : c'est le bouton qui MÈNE ici.
 *
 * <p>⭐ Il se compte lui-même, UNE fois par ouverture ({@code paywall_shown {screen: home}}, §
 * 13.8) : c'est une ROUTE, le point unique des fenêtres du flow ne la voit jamais — seule
 * exception admise au « un seul endroit ».
 *
 * <p>⭐ <b>Le compte dev&din</b> (§ 7.1 du doc commun, le contrat) : son accès permanent est le
 * bouclier de l'EN-TÊTE, en face du retour, sur tous les onglets ({@link #updateShield}) — gris,
 * puis vert et coché une fois connecté ; il se PROPOSE en haut de l'onglet de ce qui est en jeu,
 * avec les mots de cet onglet ({@link ReferralAccountHint}). ⛔ Pas de bloc en bas d'un onglet. ⛔
 * Rien de tout ça quand le compte n'existe pas dans ce binaire ({@code isAccountEnabled}).
 */
public class ReferralHomeDialog extends Dialog implements BrowtherReferralController.Listener {
    private enum Tab {
        INVITE,
        INVITATIONS,
        CODE,
        SUPPORT
    }

    private static final int DEFAULT_BROWSER_REQUEST = 0x6272;
    private static final long SLOW_MS = 6_000;

    private final Activity mActivity;
    private final BrowtherReferralPresenter.Source mSource;
    private final ReferralUi.Palette mP;
    private final BrowtherReferralController mController = BrowtherReferralController.get();
    private final Handler mHandler = new Handler(Looper.getMainLooper());

    private Tab mTab = Tab.INVITE;
    private boolean mJustRedeemed;
    private @Nullable ReferralStatus mRendered;
    private @Nullable Tab mRenderedTab;
    /**
     * Ce que le compte dev&din changeait au dernier dessin (connecté ou non, quels enjeux) : un
     * partage qui aboutit ou une connexion redessinent l'onglet SANS que le statut ait bougé.
     */
    private int mRenderedAccount = -1;
    /** Le bouclier de l'en-tête — {@code null} quand le compte n'existe pas dans ce binaire. */
    private @Nullable ImageView mShield;

    private @Nullable TextView mTitle;
    private @Nullable LinearLayout mTabs;
    private @Nullable FrameLayout mContent;
    private @Nullable ReferralConfetti mConfetti;
    /** La jauge de l'onglet Inviter : un statut qui change la RELIE, ⛔ il ne la recrée pas (sa démo). */
    private @Nullable ReferralGaugeView mGauge;

    public ReferralHomeDialog(Activity activity, BrowtherReferralPresenter.Source source) {
        super(activity, android.R.style.Theme_DeviceDefault_DayNight);
        mActivity = activity;
        mSource = source;
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

        LinearLayout column = ReferralUi.column(context);
        // ⚠️ Android 9 (§ 12.38) : la barre porte le fond de l'écran — invisible, ⛔ ne pas retirer.
        FrameLayout bar = new FrameLayout(context);
        bar.setBackgroundColor(mP.screen);
        mTitle = ReferralUi.text(context, 17, ReferralUi.SEMIBOLD, mP.text);
        mTitle.setGravity(Gravity.CENTER);
        mTitle.setSingleLine(true);
        mTitle.setEllipsize(TextUtils.TruncateAt.END);
        int barPad = ReferralUi.dp(context, 56);
        mTitle.setPadding(barPad, 0, barPad, 0);
        bar.addView(mTitle, ReferralUi.frame(ReferralUi.MATCH, ReferralUi.MATCH, Gravity.CENTER));
        ImageView close = ReferralUi.glyph(context, R.drawable.browther_intro_glyph_xmark, 16, mP.text2);
        int closePad = ReferralUi.dp(context, 14);
        close.setPadding(closePad, closePad, closePad, closePad);
        close.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        close.setContentDescription(ReferralStrings.get(context, "common.close"));
        close.setBackground(ReferralUi.pressable(null, ReferralUi.withAlpha(mP.text, 0.1f), ReferralUi.dp(context, 22)));
        close.setOnClickListener(v -> dismiss());
        int closeSize = ReferralUi.dp(context, 44);
        // ⭐ Avec le compte, la croix passe au DÉBUT : la fin est au bouclier, « en face du retour »
        // (comme sur iOS). Sans compte dans ce binaire, l'en-tête reste celui d'avant.
        boolean account = mController.isAccountEnabled();
        FrameLayout.LayoutParams closeParams =
                ReferralUi.frame(
                        closeSize,
                        closeSize,
                        (account ? Gravity.START : Gravity.END) | Gravity.CENTER_VERTICAL);
        closeParams.setMarginStart(ReferralUi.dp(context, 6));
        closeParams.setMarginEnd(ReferralUi.dp(context, 6));
        bar.addView(close, closeParams);
        if (account) {
            // ⭐ L'accès PERMANENT au compte dev&din (§ 7.1) : jamais derrière un défilement — dans
            // l'en-tête, donc sur TOUS les onglets, et dès l'attente du statut.
            ImageView shield =
                    ReferralUi.glyph(context, R.drawable.browther_referral_glyph_shield, 22, mP.text2);
            int shieldPad = ReferralUi.dp(context, 11);
            shield.setPadding(shieldPad, shieldPad, shieldPad, shieldPad);
            shield.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
            shield.setBackground(
                    ReferralUi.pressable(
                            null, ReferralUi.withAlpha(mP.text, 0.1f), ReferralUi.dp(context, 22)));
            shield.setOnClickListener(
                    v -> {
                        ReferralUi.tick(v);
                        BrowtherReferralPresenter.openAccount(
                                mActivity, BrowtherReferralPresenter.AccountOrigin.HOME, false);
                    });
            FrameLayout.LayoutParams shieldParams =
                    ReferralUi.frame(closeSize, closeSize, Gravity.END | Gravity.CENTER_VERTICAL);
            shieldParams.setMarginEnd(ReferralUi.dp(context, 6));
            bar.addView(shield, shieldParams);
            mShield = shield;
            updateShield();
        }
        column.addView(bar, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 52)));

        mTabs = ReferralUi.row(context);
        LinearLayout.LayoutParams tabsParams =
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 8));
        tabsParams.leftMargin = ReferralUi.dp(context, 16);
        tabsParams.rightMargin = ReferralUi.dp(context, 16);
        tabsParams.bottomMargin = ReferralUi.dp(context, 12);
        column.addView(mTabs, tabsParams);

        mContent = new FrameLayout(context);
        mContent.setBackgroundColor(mP.screen);
        column.addView(mContent, new LinearLayout.LayoutParams(ReferralUi.MATCH, 0, 1));
        root.addView(column, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));

        mConfetti = new ReferralConfetti(context);
        root.addView(mConfetti, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));

        setContentView(root);
        Window window = getWindow();
        if (window != null) {
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
            window.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(mP.screen));
            window.setStatusBarColor(mP.screen);
            window.setNavigationBarColor(mP.screen);
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
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

        // ⭐ L'écran Parrainage compte son affichage UNE fois par ouverture (§ 13.8).
        BrowtherReferralPresenter.countShown("home", mSource, false, null);
        render(true);
    }

    @Override
    protected void onStart() {
        super.onStart();
        mController.addListener(this);
        mController.boot();
        mController.refresh();
        // Une connexion Google / Apple part dans un onglet : cet écran, plein écran, le couvrirait
        // — le présentateur doit pouvoir le fermer (`dismissPages`).
        BrowtherReferralPresenter.pageShown(this);
        render(false);
    }

    @Override
    protected void onStop() {
        super.onStop();
        mController.removeListener(this);
        BrowtherReferralPresenter.pageHidden(this);
        mHandler.removeCallbacksAndMessages(null);
    }

    @Override
    public void onReferralChanged() {
        render(false);
    }

    private void celebrate() {
        if (mConfetti != null && !ReferralUi.reduceMotion(getContext())) mConfetti.fire();
    }

    // -------------------- Rendu --------------------

    /**
     * Gris tant que personne n'est connecté, vert et coché ensuite — son libellé d'accessibilité
     * dit ce qu'il ouvre.
     */
    private void updateShield() {
        ImageView shield = mShield;
        if (shield == null) return;
        boolean connected = mController.account() != null;
        shield.setImageResource(
                connected
                        ? R.drawable.browther_referral_glyph_shield_check
                        : R.drawable.browther_referral_glyph_shield);
        shield.setImageTintList(
                android.content.res.ColorStateList.valueOf(connected ? mP.green : mP.text2));
        shield.setContentDescription(
                ReferralStrings.get(getContext(), connected ? "account.manage" : "account.connect"));
    }

    /** Ce que le compte change à l'écran : connecté ou non, et les enjeux de chaque onglet. */
    private int accountKey() {
        if (!mController.isAccountEnabled()) return 0;
        ReferralAccountStakes stakes = mController.accountStakes();
        return 1
                | (mController.account() != null ? 2 : 0)
                | (stakes.invite ? 4 : 0)
                | (stakes.invitations ? 8 : 0)
                | (stakes.referee ? 16 : 0)
                | (stakes.paid ? 32 : 0);
    }

    /** La rangée du compte pour cet onglet — {@code null} quand il n'y a rien à proposer. */
    private @Nullable View accountHint(ReferralAccountStake stake) {
        return ReferralAccountHint.of(mActivity, mP, stake, false);
    }

    private void render(boolean force) {
        if (mContent == null || mTitle == null || mTabs == null) return;
        updateShield();
        ReferralStatus status = mController.known();
        if (status == null) {
            mTitle.setText(ReferralStrings.get(getContext(), "home.title"));
            mTabs.setVisibility(View.GONE);
            if (mRendered == null && mRenderedTab == null && !force && mContent.getChildCount() > 0) {
                return;
            }
            mRendered = null;
            mRenderedTab = null;
            mGauge = null;
            mContent.removeAllViews();
            mContent.addView(pendingView());
            return;
        }
        mTabs.setVisibility(View.VISIBLE);
        mTitle.setText(title());
        int account = accountKey();
        if (!force
                && status.equals(mRendered)
                && mTab == mRenderedTab
                && account == mRenderedAccount) {
            return;
        }
        mRenderedAccount = account;
        // Le même onglet, un statut neuf (ou la rangée du compte qui arrive juste après un
        // partage) : la jauge est RELIÉE, pas recréée (sa démo ne rejoue pas).
        if (!force
                && mTab == Tab.INVITE
                && mRenderedTab == Tab.INVITE
                && mGauge != null
                && mRendered != null) {
            mRendered = status;
            buildTabs();
            rebuildInviteKeepingGauge(status);
            return;
        }
        mRendered = status;
        mRenderedTab = mTab;
        buildTabs();
        mContent.removeAllViews();
        mGauge = null;
        switch (mTab) {
            case INVITATIONS:
                mContent.addView(invitationsTab(status));
                break;
            case CODE:
                mContent.addView(codeTab(status));
                break;
            case SUPPORT:
                mContent.addView(supportTab(status));
                break;
            case INVITE:
            default:
                mContent.addView(inviteTab(status, null));
                break;
        }
    }

    private void rebuildInviteKeepingGauge(ReferralStatus status) {
        if (mContent == null || mGauge == null) return;
        ReferralGaugeView gauge = mGauge;
        if (gauge.getParent() instanceof ViewGroup) ((ViewGroup) gauge.getParent()).removeView(gauge);
        mContent.removeAllViews();
        mContent.addView(inviteTab(status, gauge));
    }

    private String title() {
        Context context = getContext();
        switch (mTab) {
            case INVITATIONS:
                return ReferralStrings.get(context, "home.listHead");
            case CODE:
                return ReferralStrings.get(context, "home.asReferee");
            case SUPPORT:
                return ReferralStrings.get(context, "home.tabs.support");
            case INVITE:
            default:
                return ReferralStrings.get(context, "home.title");
        }
    }

    private void choose(Tab next) {
        if (next == mTab) return;
        if (mTabs != null) ReferralUi.tick(mTabs);
        // ⭐ On vient ici EXPRÈS : c'est le pendant de « Choisir ma formule » (§ 12.26).
        if (next == Tab.SUPPORT) {
            mController.note("paywall_action", false, "screen", "home", "action", "billing");
        }
        mTab = next;
        render(true);
    }

    private void buildTabs() {
        if (mTabs == null) return;
        Context context = getContext();
        mTabs.removeAllViews();
        int pad = ReferralUi.dp(context, 4);
        mTabs.setPadding(pad, pad, pad, pad);
        mTabs.setBackground(ReferralUi.rounded(mP.track, ReferralUi.dp(context, 14)));
        addTab(Tab.INVITE, "home.tabs.invite", R.drawable.browther_intro_glyph_people);
        addTab(Tab.INVITATIONS, "home.tabs.invitations", R.drawable.browther_referral_glyph_seal);
        addTab(Tab.CODE, "home.tabs.code", R.drawable.browther_referral_glyph_gift);
        // ⭐ Toujours présent sur Android : la porte factice est le parcours du paiement (§ 12.27).
        if (mController.billingAvailable()) {
            addTab(Tab.SUPPORT, "home.tabs.support", R.drawable.browther_referral_glyph_heart);
        } else if (mTab == Tab.SUPPORT) {
            mTab = Tab.INVITE;
        }
    }

    private void addTab(Tab tab, String key, int icon) {
        Context context = getContext();
        boolean on = tab == mTab;
        LinearLayout item = ReferralUi.column(context);
        item.setGravity(Gravity.CENTER);
        item.setMinimumHeight(ReferralUi.dp(context, 52));
        int padV = ReferralUi.dp(context, 6);
        item.setPadding(0, padV, 0, padV);
        if (on) {
            item.setBackground(ReferralUi.rounded(mP.panel, ReferralUi.dp(context, 11)));
            item.setElevation(ReferralUi.dp(context, 1.5f));
        }
        int color = on ? mP.text : mP.text2;
        ImageView glyph = ReferralUi.glyph(context, icon, 18, color);
        LinearLayout.LayoutParams glyphParams =
                new LinearLayout.LayoutParams(ReferralUi.dp(context, 18), ReferralUi.dp(context, 18));
        glyphParams.gravity = Gravity.CENTER_HORIZONTAL;
        item.addView(glyph, glyphParams);
        String label = ReferralStrings.get(context, key);
        TextView text =
                ReferralUi.text(context, label, 12, on ? ReferralUi.SEMIBOLD : ReferralUi.MEDIUM, color);
        text.setSingleLine(true);
        text.setEllipsize(TextUtils.TruncateAt.END);
        text.setGravity(Gravity.CENTER);
        item.addView(text, ReferralUi.linear(ReferralUi.WRAP, ReferralUi.WRAP, ReferralUi.dp(context, 3)));
        item.setClickable(true);
        item.setFocusable(true);
        item.setContentDescription(label);
        item.setSelected(on);
        item.setOnClickListener(v -> choose(tab));
        mTabs.addView(item, new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1));
    }

    // -------------------- L'attente (trois états, jamais deux) --------------------

    private View pendingView() {
        Context context = getContext();
        LinearLayout column = ReferralUi.column(context);
        column.setGravity(Gravity.CENTER);
        int pad = ReferralUi.dp(context, 32);
        column.setPadding(pad, pad, pad, pad);
        ProgressBar spinner = new ProgressBar(context);
        spinner.setIndeterminate(true);
        column.addView(spinner, new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP));
        TextView slow = ReferralUi.footnote(context, mP, ReferralStrings.get(context, "home.unreachable"));
        slow.setVisibility(View.GONE);
        column.addView(slow, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 14)));
        View retry =
                ReferralUi.secondaryButton(
                        context, mP, ReferralStrings.get(context, "home.retry"), mController::refresh);
        retry.setVisibility(View.GONE);
        LinearLayout.LayoutParams retryParams =
                new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
        retryParams.topMargin = ReferralUi.dp(context, 14);
        retryParams.gravity = Gravity.CENTER_HORIZONTAL;
        column.addView(retry, retryParams);
        mHandler.postDelayed(
                () -> {
                    slow.setVisibility(View.VISIBLE);
                    retry.setVisibility(View.VISIBLE);
                },
                SLOW_MS);
        column.setLayoutParams(new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        return column;
    }

    // -------------------- Onglet « Inviter » --------------------

    /**
     * L'état, la carte, le partage, la jauge — ⚠️ la couverture a un libellé pour CHAQUE cas
     * connu, « avant l'annonce » compris (§ 12.11). ⛔ On n'annonce jamais une pause qui n'est pas là.
     */
    private View inviteTab(ReferralStatus status, @Nullable ReferralGaugeView keptGauge) {
        Context context = getContext();
        Instant now = Instant.now();
        AccessState access = new AccessState(status);
        MilestoneScale scale = new MilestoneScale(status);
        int validated = status.milestones.validated;
        LinearLayout column = pageColumn(context);

        // ⭐ Le code est parti (un partage vient d'aboutir), ou a déjà servi : « Mets ton code à
        // l'abri », en haut, tout de suite (§ 7.1).
        View hint = accountHint(ReferralAccountStake.INVITE);
        if (hint != null) {
            LinearLayout.LayoutParams hintParams =
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP);
            hintParams.bottomMargin = ReferralUi.dp(context, 18);
            column.addView(hint, hintParams);
        }

        LinearLayout head = ReferralUi.row(context);
        TextView label =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "home.coverA")
                                .toUpperCase(ReferralFormat.locale(context)),
                        12,
                        ReferralUi.SEMIBOLD,
                        mP.text2);
        label.setLetterSpacing(0.05f);
        head.addView(label, new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP));
        ImageView info = ReferralUi.glyph(context, R.drawable.browther_referral_glyph_info, 15, mP.text2);
        int infoPad = ReferralUi.dp(context, 8);
        info.setPadding(infoPad, infoPad, infoPad, infoPad);
        info.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        info.setContentDescription(ReferralStrings.get(context, "home.whatExtras"));
        info.setOnClickListener(v -> showWhatExtras(status, access));
        int infoSize = ReferralUi.dp(context, 32);
        head.addView(info, new LinearLayout.LayoutParams(infoSize, infoSize));
        column.addView(head);

        column.addView(
                ReferralUi.text(context, coverage(status, access, now), 20, ReferralUi.SEMIBOLD, mP.text));
        if (access.isPaused(now) && !access.lifetime) {
            column.addView(
                    ReferralUi.text(
                            context,
                            ReferralStrings.get(context, "home.whyPaused"),
                            13,
                            ReferralUi.REGULAR,
                            mP.gold),
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 6)));
        }
        // ⛔ Rien à zéro (§ 12.26) : le compte n'apparaît que s'il y a quelque chose à compter.
        if (validated > 0) {
            column.addView(
                    ReferralUi.text(
                            context,
                            ReferralUi.rich(progressText(status, scale, validated, access.lifetime)),
                            15,
                            ReferralUi.REGULAR,
                            mP.text2),
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 6)));
        }

        ReferralCodeCard card =
                new ReferralCodeCard(
                        context,
                        status,
                        () -> {
                            // ⭐ Copier EST un partage abouti (§ 12.20) : 3 jours offerts compris.
                            mController.note(
                                    "referral_shared",
                                    false,
                                    "screen",
                                    "home",
                                    "result",
                                    "copied",
                                    "format",
                                    ReferralSharing.Format.MESSAGE.wire);
                            mController.shareDone("home", false);
                        });
        LinearLayout.LayoutParams cardParams =
                new LinearLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP);
        cardParams.topMargin = ReferralUi.dp(context, 18);
        cardParams.gravity = Gravity.CENTER_HORIZONTAL;
        column.addView(card, cardParams);

        column.addView(
                shareButton(status),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 18)));
        column.addView(
                statusButton(status),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 8)));
        column.addView(
                ReferralUi.footnote(
                        context,
                        mP,
                        ReferralStrings.plural(
                                context, "invite.foot", ReferralProduct.validationTargetDays)),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 8)));

        ReferralGaugeView gauge =
                keptGauge != null
                        ? keptGauge
                        : new ReferralGaugeView(
                                context, ReferralGaugeView.Mode.SPRING, true, false, this::celebrate);
        gauge.bind(validated, scale);
        mGauge = gauge;
        column.addView(
                gauge, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 18)));
        return scroll(column, false);
    }

    private String coverage(ReferralStatus status, AccessState access, Instant now) {
        Context context = getContext();
        CoverageLabel label = new CoverageLabel(status, access, now);
        switch (label.kind) {
            case LIFETIME:
                return ReferralStrings.get(context, "home.coverLifetime");
            case PAID:
                return ReferralStrings.get(context, "home.coverPaid");
            case PAUSED:
                return ReferralStrings.get(context, "home.coverPaused");
            case UNTIL:
                return ReferralStrings.fill(
                        ReferralStrings.get(context, "home.coverUntil"),
                        "date",
                        ReferralFormat.date(context, label.until, true));
            case OFFERED:
            default:
                return ReferralStrings.get(context, "home.coverOpen");
        }
    }

    private String progressText(
            ReferralStatus status, MilestoneScale scale, int validated, boolean lifetime) {
        Context context = getContext();
        String months = String.valueOf(status.milestones.monthsEarned);
        MilestoneScale.Next next = scale.next(validated);
        if (lifetime || next == null) {
            return ReferralStrings.plural(context, "home.progressLife", validated);
        }
        if (next.lifetime) {
            return ReferralStrings.fill(
                    ReferralStrings.plural(context, "home.progressToLife", validated),
                    "months", months,
                    "left", String.valueOf(next.remaining));
        }
        return ReferralStrings.fill(
                ReferralStrings.plural(context, "home.progress", validated),
                "months", months,
                "left", String.valueOf(next.remaining),
                "bonus", String.valueOf(next.bonusMonths));
    }

    /** « Qu'est-ce que les fonctionnalités supplémentaires ? » : la liste, avec l'état du moment. */
    private void showWhatExtras(ReferralStatus status, AccessState access) {
        Context context = getContext();
        LinearLayout column = ReferralUi.column(context);
        int pad = ReferralUi.dp(context, 20);
        column.setPadding(pad, ReferralUi.dp(context, 8), pad, 0);
        column.addView(
                ReferralUi.featureList(
                        context, mP, new ExtrasState(status, access, Instant.now()), false));
        new AlertDialog.Builder(context)
                .setTitle(ReferralStrings.get(context, "home.whatExtras"))
                .setView(column)
                .setPositiveButton(ReferralStrings.get(context, "common.close"), null)
                .show();
    }

    /** 🔴 Partager ne crée AUCUNE invitation : un partage abouti n'ouvre droit qu'aux 3 jours (§ 4). */
    private View shareButton(ReferralStatus status) {
        Context context = getContext();
        return ReferralUi.primaryButton(
                context,
                mP,
                ReferralStrings.get(context, "invite.share"),
                null,
                R.drawable.browther_referral_glyph_share,
                () -> ReferralSharing.share(mActivity, status, "home", false, result -> {}));
    }

    /**
     * ⭐ Le 2ᵉ geste, sous « Partager mon code » : un contour, ⭐ un libellé qui CITE WhatsApp
     * (« Publier en statut WhatsApp ») — l'image dit « Clique sur le lien en dessous », vrai
     * seulement là où le lien devient la légende (§ 9).
     */
    private View statusButton(ReferralStatus status) {
        Context context = getContext();
        return ReferralUi.secondaryButton(
                context,
                mP,
                ReferralStrings.get(context, "invite.shareStatus"),
                R.drawable.browther_referral_glyph_status,
                () -> ReferralSharing.shareStatus(mActivity, status, "home", false, result -> {}));
    }

    // -------------------- Onglet « Invitations » --------------------

    private View invitationsTab(ReferralStatus status) {
        Context context = getContext();
        List<InvitationItem> invitations = ReferralInvitations.known(status.invitations.items);
        // ⭐ Le seul signal d'« ouverture » qu'on connaisse : les clics sur LE lien, tous proches
        // confondus — ⛔ jamais par invitation (§ 12.1).
        int opens = status.referral.clicks == null ? 0 : status.referral.clicks;
        if (invitations.isEmpty()) {
            LinearLayout extra = ReferralUi.column(context);
            extra.addView(
                    shareButton(status),
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 6)));
            if (opens > 0) {
                extra.addView(
                        ReferralUi.footnote(
                                context, mP, ReferralStrings.plural(context, "home.linkOpens", opens)),
                        ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 10)));
            }
            return centeredState(
                    R.drawable.browther_referral_glyph_share,
                    ReferralUi.Tone.GREEN,
                    ReferralStrings.get(context, "home.empty"),
                    ReferralStrings.get(context, "home.emptyHint"),
                    extra,
                    null);
        }
        LinearLayout column = pageColumn(context);
        // ⭐ Une invitation en cours ou validée : « Mets tes invitations à l'abri ».
        View hint = accountHint(ReferralAccountStake.INVITATIONS);
        if (hint != null) {
            LinearLayout.LayoutParams hintParams =
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP);
            hintParams.bottomMargin = ReferralUi.dp(context, 12);
            column.addView(hint, hintParams);
        }
        if (opens > 0) {
            TextView line =
                    ReferralUi.text(
                            context,
                            ReferralStrings.plural(context, "home.linkOpens", opens),
                            13,
                            ReferralUi.REGULAR,
                            mP.text2);
            column.addView(line, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        }
        MilestoneScale scale = new MilestoneScale(status);
        for (InvitationItem item : invitations) {
            column.addView(
                    invitationRow(item, scale),
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 10)));
        }
        column.addView(
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "home.legend"),
                        13,
                        ReferralUi.REGULAR,
                        mP.text3),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 12)));
        return scroll(column, false);
    }

    /**
     * Deux états, deux couleurs : or = en cours (un proche a utilisé le code), vert = validée (+1
     * mois, et la ligne ★ quand elle a fait franchir un palier). ⛔ Jamais « envoyée », ⛔ jamais un
     * nom.
     */
    private View invitationRow(InvitationItem item, MilestoneScale scale) {
        Context context = getContext();
        boolean validated = item.status == InvitationStatus.VALIDATED;
        int tone = validated ? mP.green : mP.gold;
        int target = ReferralProduct.validationTargetDays;
        LinearLayout card = ReferralUi.column(context);
        int pad = ReferralUi.dp(context, 12);
        card.setPadding(pad, pad, pad, pad);
        card.setBackground(ReferralUi.rounded(mP.panel, ReferralUi.dp(context, 14)));

        LinearLayout top = ReferralUi.row(context);
        TextView pill =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(
                                context,
                                validated ? "invitations.validated" : "invitations.inProgress"),
                        12,
                        ReferralUi.SEMIBOLD,
                        tone);
        int padH = ReferralUi.dp(context, 8);
        int padV = ReferralUi.dp(context, 3);
        pill.setPadding(padH, padV, padH, padV);
        pill.setBackground(ReferralUi.rounded(ReferralUi.withAlpha(tone, 0.12f), ReferralUi.dp(context, 100)));
        top.addView(pill, new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP));
        Instant date = ReferralDate.parse(validated ? item.validatedAt : item.installedAt);
        if (date != null) {
            TextView when =
                    ReferralUi.text(
                            context,
                            ReferralFormat.date(context, date, false),
                            12,
                            ReferralUi.REGULAR,
                            mP.text2);
            LinearLayout.LayoutParams whenParams =
                    new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
            whenParams.setMarginStart(ReferralUi.dp(context, 8));
            top.addView(when, whenParams);
        }
        top.addView(new View(context), new LinearLayout.LayoutParams(0, 1, 1));
        if (validated) {
            top.addView(
                    ReferralUi.text(
                            context,
                            ReferralStrings.plural(context, "invitations.months", 1),
                            17,
                            ReferralUi.SEMIBOLD,
                            mP.green));
        }
        card.addView(top, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));

        int gap = ReferralUi.dp(context, 6);
        if (validated) {
            card.addView(
                    ReferralUi.text(
                            context,
                            ReferralStrings.plural(context, "invitations.rowValidated", target),
                            13,
                            ReferralUi.REGULAR,
                            mP.text2),
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, gap));
            MilestoneBonus bonus = item.milestone ? scale.milestone(item.creditedMonths) : null;
            if (bonus != null) {
                String line =
                        ReferralStrings.fill(
                                ReferralStrings.plural(context, "invitations.milestone", bonus.months),
                                "at",
                                String.valueOf(bonus.at));
                card.addView(
                        ReferralUi.text(context, "★ " + line, 13, ReferralUi.MEDIUM, mP.gold),
                        ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, gap));
            }
        } else {
            Integer left = ReferralInvitations.daysLeft(item);
            if (left != null) {
                card.addView(
                        ReferralUi.text(
                                context,
                                ReferralStrings.plural(context, "invitations.rowInProgress", left),
                                13,
                                ReferralUi.REGULAR,
                                mP.text2),
                        ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, gap));
                card.addView(
                        new Meter(context, ReferralInvitations.ratio(item.progress)),
                        ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 6), gap));
            } else {
                card.addView(
                        ReferralUi.text(
                                context,
                                ReferralStrings.plural(
                                        context, "invitations.rowInProgressUnknown", target),
                                13,
                                ReferralUi.REGULAR,
                                mP.text2),
                        ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, gap));
            }
        }
        return card;
    }

    // -------------------- Onglet « Code reçu » --------------------

    /**
     * Quand on t'invite (§ 5.3) : saisir le code d'un proche, puis suivre sa propre validation. ⭐
     * Sans code saisi, c'est l'écran O lui-même. ⛔ Rien du proche qui a invité n'y figure.
     */
    private View codeTab(ReferralStatus status) {
        Context context = getContext();
        ReferralStatus.ReferredBy referred = status.referredBy;
        if (referred != null && !mJustRedeemed) return refereeCard(referred);
        LinearLayout column = ReferralUi.column(context);
        int pad = ReferralUi.dp(context, 24);
        column.setPadding(pad, pad, pad, pad);
        column.setBackgroundColor(mP.screen);
        ReferralCodeEntry entry =
                new ReferralCodeEntry(
                        context,
                        "manual",
                        false,
                        () -> {
                            mJustRedeemed = true;
                            celebrate();
                        });
        column.addView(entry, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        // ⭐ Le code d'un proche vient d'être saisi : « Mets ton mois offert à l'abri », sur l'écran
        // où l'on EST (§ 7.1) — elle arrive avec le statut qui porte le code, au redessin.
        View hint = mJustRedeemed ? accountHint(ReferralAccountStake.REFEREE) : null;
        if (hint != null) {
            column.addView(
                    hint, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 24)));
        }
        return scroll(column, true);
    }

    private View refereeCard(ReferralStatus.ReferredBy referred) {
        Context context = getContext();
        boolean done = referred.status == ReferralStatus.ReferredBy.Status.VALIDATED;
        int target = ReferralProduct.validationTargetDays;
        Integer left = ReferralInvitations.daysLeft(referred.progress);
        String message =
                done
                        ? ReferralStrings.get(context, "referee.done")
                        : left != null
                                ? ReferralStrings.plural(context, "referee.progress", left)
                                : ReferralStrings.plural(context, "referee.hint", target);
        LinearLayout extra = ReferralUi.column(context);
        ValidationProgress progress = referred.progress;
        if (!done && progress != null) {
            LinearLayout meter = ReferralUi.column(context);
            meter.addView(
                    new Meter(context, ReferralInvitations.ratio(progress)),
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 6)));
            meter.addView(
                    ReferralUi.footnote(
                            context,
                            mP,
                            ReferralStrings.fill(
                                    ReferralStrings.plural(
                                            context, "referee.meter", (long) progress.target),
                                    "current",
                                    String.valueOf((int) progress.current))),
                    ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 6)));
            LinearLayout.LayoutParams meterParams =
                    new LinearLayout.LayoutParams(ReferralUi.dp(context, 280), ReferralUi.WRAP);
            meterParams.gravity = Gravity.CENTER_HORIZONTAL;
            extra.addView(meter, meterParams);
        }
        View button;
        if (!done) {
            // ⭐ Ce qui valide l'invitation du proche, c'est Browther PAR DÉFAUT (§ 9) : LE geste
            // attendu, donc bouton PRINCIPAL (⛔ pas un contour discret, recette iOS 2026-09-24).
            button =
                    ReferralUi.primaryButton(
                            context,
                            mP,
                            ReferralStrings.get(context, "referee.setDefault"),
                            null,
                            0,
                            this::openDefaultBrowserChoice);
        } else {
            button =
                    ReferralUi.primaryButton(
                            context,
                            mP,
                            ReferralStrings.get(context, "referee.inviteToo"),
                            null,
                            0,
                            () -> choose(Tab.INVITE));
        }
        extra.addView(button, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 14)));
        // ⭐ Le code d'un proche a été saisi : « Mets ton mois offert à l'abri ». ⚠️ L'onglet est
        // centré : la rangée, elle, se lit depuis le début de la ligne et prend la largeur.
        View hint = accountHint(ReferralAccountStake.REFEREE);
        if (hint != null) {
            extra.addView(
                    hint, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 18)));
        }
        return centeredState(
                done ? R.drawable.browther_intro_glyph_check : R.drawable.browther_referral_glyph_gift,
                ReferralUi.Tone.GOLD,
                ReferralStrings.get(context, "referee.title"),
                message,
                extra,
                null);
    }

    /**
     * 🔴 Dépose là où l'on CHOISIT son navigateur (§ 2.15 : ⛔ jamais la fiche de l'app) : la
     * feuille système du rôle « navigateur », sinon les réglages des applications par défaut.
     */
    private void openDefaultBrowserChoice() {
        RoleManager roles = mActivity.getSystemService(RoleManager.class);
        if (roles != null
                && roles.isRoleAvailable(RoleManager.ROLE_BROWSER)
                && !roles.isRoleHeld(RoleManager.ROLE_BROWSER)) {
            try {
                mActivity.startActivityForResult(
                        roles.createRequestRoleIntent(RoleManager.ROLE_BROWSER),
                        DEFAULT_BROWSER_REQUEST);
                return;
            } catch (ActivityNotFoundException e) {
                // Pas de feuille du rôle sur cet appareil : les réglages.
            }
        }
        try {
            mActivity.startActivity(new Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS));
        } catch (ActivityNotFoundException e) {
            // Rien à ouvrir : on reste sur l'écran.
        }
    }

    // -------------------- Onglet « Soutenir » --------------------

    /**
     * On vient ici EXPRÈS (§ 12.26) : ce que le soutien débloque, puis l'écran 7 — sur Android, la
     * PORTE FACTICE (§ 12.27) : le parcours du vrai paiement, jusqu'au toucher de « Je soutiens ».
     */
    private View supportTab(ReferralStatus status) {
        Context context = getContext();
        LinearLayout extra = ReferralUi.column(context);
        extra.addView(
                ReferralUi.featureList(
                        context,
                        mP,
                        new ExtrasState(status, new AccessState(status), Instant.now()),
                        true),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 4)));
        extra.addView(
                ReferralUi.primaryButton(
                        context,
                        mP,
                        ReferralStrings.fill(
                                ReferralStrings.get(context, "support.money"),
                                "price",
                                ReferralPricing.monthly),
                        null,
                        R.drawable.browther_referral_glyph_heart,
                        () ->
                                BrowtherReferralPresenter.present(
                                        mActivity,
                                        ReferralScreen.billing(),
                                        BrowtherReferralPresenter.Source.USER,
                                        false)),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 16)));
        return centeredState(
                R.drawable.browther_referral_glyph_heart,
                ReferralUi.Tone.GOLD,
                ReferralStrings.get(context, "billing.title"),
                ReferralStrings.get(context, "billing.body"),
                extra,
                // ⭐ Abonné : c'est ICI qu'est son abonnement, donc ici que le compte se propose
                // (§ 7.1) — ⛔ pas sur « Inviter ».
                accountHint(ReferralAccountStake.PAID));
    }

    // -------------------- Briques --------------------

    private LinearLayout pageColumn(Context context) {
        LinearLayout column = ReferralUi.column(context);
        int pad = ReferralUi.dp(context, 16);
        column.setPadding(pad, 0, pad, ReferralUi.dp(context, 32));
        column.setBackgroundColor(mP.screen);
        return column;
    }

    /**
     * Un contenu qui défile. ⚠️ Android 9 (§ 12.38) : le conteneur porte le fond de l'écran ;
     * {@code fill} = le contenu prend au moins la hauteur visible (un onglet peu rempli se centre).
     */
    private ScrollView scroll(View content, boolean fill) {
        Context context = getContext();
        ScrollView scroll = new ScrollView(context);
        scroll.setBackgroundColor(mP.screen);
        scroll.setFillViewport(fill);
        scroll.setClipToPadding(false);
        FrameLayout holder = new FrameLayout(context);
        holder.setBackgroundColor(mP.screen);
        FrameLayout.LayoutParams params =
                new FrameLayout.LayoutParams(
                        Math.min(
                                ReferralUi.dp(context, 560),
                                context.getResources().getDisplayMetrics().widthPixels),
                        fill ? ReferralUi.MATCH : ReferralUi.WRAP,
                        Gravity.CENTER_HORIZONTAL);
        holder.addView(content, params);
        scroll.addView(holder, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));
        scroll.setLayoutParams(new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        return scroll;
    }

    /**
     * La grammaire d'un onglet peu rempli (§ 12.26) : une icône dans un rond, un titre, une phrase
     * — CENTRÉS.
     *
     * @param top ce qui se pose EN HAUT de l'onglet, au-dessus du contenu centré (la rangée du
     *     compte), ou {@code null}.
     */
    private View centeredState(
            int icon,
            ReferralUi.Tone tone,
            String title,
            @Nullable String message,
            View extra,
            @Nullable View top) {
        Context context = getContext();
        LinearLayout column = ReferralUi.column(context);
        column.setGravity(Gravity.CENTER);
        int pad = ReferralUi.dp(context, 24);
        column.setPadding(pad, pad, pad, pad);
        column.setBackgroundColor(mP.screen);
        column.addView(ReferralUi.roundIcon(context, mP, icon, tone, 76));
        TextView titleView = ReferralUi.text(context, title, 20, ReferralUi.SEMIBOLD, mP.text);
        titleView.setGravity(Gravity.CENTER_HORIZONTAL);
        titleView.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
        column.addView(titleView, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 18)));
        if (message != null) {
            TextView body = ReferralUi.text(context, ReferralUi.rich(message), 16, ReferralUi.REGULAR, mP.text2);
            body.setGravity(Gravity.CENTER_HORIZONTAL);
            body.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
            column.addView(body, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 8)));
        }
        column.addView(extra, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 18)));
        if (top == null) return scroll(column, true);
        // La rangée en tête, le contenu centré dans ce qu'il reste de la hauteur.
        LinearLayout outer = ReferralUi.column(context);
        outer.setBackgroundColor(mP.screen);
        LinearLayout.LayoutParams topParams = ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP);
        int side = ReferralUi.dp(context, 16);
        topParams.leftMargin = side;
        topParams.rightMargin = side;
        outer.addView(top, topParams);
        outer.addView(column, new LinearLayout.LayoutParams(ReferralUi.MATCH, 0, 1));
        return scroll(outer, true);
    }

    /** La barre de progression d'une invitation en cours, toujours de gauche à droite. */
    private final class Meter extends View {
        private final Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float mRatio;

        Meter(Context context, double ratio) {
            super(context);
            mRatio = (float) Math.max(0, Math.min(1, ratio));
            setLayoutDirection(LAYOUT_DIRECTION_LTR);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            float h = getHeight();
            float r = h / 2;
            mPaint.setColor(mP.track);
            canvas.drawRoundRect(0, 0, getWidth(), h, r, r, mPaint);
            mPaint.setColor(mP.goldFill);
            canvas.drawRoundRect(0, 0, getWidth() * mRatio, h, r, r, mPaint);
        }
    }
}
