/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.BrowtherReferralPresenter.FlowModel;
import org.chromium.chrome.browser.browther_referral.BrowtherReferralPresenter.Source;
import org.chromium.chrome.browser.browther_referral.core.BillingPeriod;
import org.chromium.chrome.browser.browther_referral.core.ExtrasState;
import org.chromium.chrome.browser.browther_referral.core.MilestoneScale;
import org.chromium.chrome.browser.browther_referral.core.ReferralDate;
import org.chromium.chrome.browser.browther_referral.core.ReferralPricing;
import org.chromium.chrome.browser.browther_referral.core.ReferralProduct;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * La pile plein écran du flow (O, 0, 2, 2b, 4 par-dessus 2b, 7 et le cadeau) — pendant de {@code
 * ReferralFlowView} et {@code ReferralFlowShell} (iOS, {@code ReferralFlowViews.swift}).
 *
 * <p>⚠️ <b>Une SEULE vue à la fois</b> (§ 12.38 du doc commun) : sur Android une pile de couches
 * laisse le pied de la fenêtre du dessous se dessiner par-dessus celle du dessus. La pile n'est
 * qu'un état ({@link FlowModel}) ; seule la fenêtre du dessus est construite.
 *
 * <p>Gabarit (§ 12.26) : une fenêtre plus haute que son contenu a le contenu CENTRÉ et les boutons
 * EN BAS ; un contenu qui déborde défile, ⛔ jamais rogné. Le retour se voit deux fois (§ 12.16) :
 * une flèche en haut et « Retour » en toutes lettres en bas. La croix n'existe que sur une fenêtre
 * qui n'ATTEND pas d'action (§ 12.14).
 *
 * <p>🔴 Sur Android le paiement est une PORTE FACTICE (§ 12.27) : l'écran 7 est celui du vrai
 * paiement, jusqu'au toucher de « Je soutiens · … », qui offre un mois ({@code
 * BrowtherReferralController.gift}) et ouvre « C'est cadeau ! ». ⛔ Aucune fausse page de carte.
 */
public final class ReferralFlowDialog extends Dialog implements BrowtherReferralController.Listener {
    private static final int MAX_WIDTH_DP = 560;

    private final Activity mActivity;
    private final ReferralScreen mRoot;
    private final Source mSource;
    private final boolean mPreview;
    private final BrowtherReferralController mController = BrowtherReferralController.get();
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final ReferralUi.Palette mPalette;

    private FrameLayout mStage;
    private ReferralConfetti mConfetti;
    private @Nullable FlowModel mModel;
    private @Nullable View mCurrent;
    private @Nullable View mFooter;
    /** Le statut était-il connu au dernier dessin ? (4 attend le code pour montrer sa carte.) */
    private boolean mRenderedWithStatus;
    /** Le cadeau n'a sa fête qu'une fois par écran posé. */
    private boolean mGiftCelebrated;

    public ReferralFlowDialog(Activity activity, ReferralScreen root, Source source, boolean preview) {
        super(
                activity,
                ReferralUi.palette(activity).dark
                        ? android.R.style.Theme_Material_NoActionBar
                        : android.R.style.Theme_Material_Light_NoActionBar);
        mActivity = activity;
        mRoot = root;
        mSource = source;
        mPreview = preview;
        mPalette = ReferralUi.palette(activity);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Context context = getContext();
        FrameLayout root = new FrameLayout(context);
        // 🔴 § 12.38 : un fond explicite, égal à celui de l'écran.
        root.setBackgroundColor(mPalette.screen);
        mStage = new FrameLayout(context);
        mStage.setBackgroundColor(mPalette.screen);
        root.addView(mStage, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        mConfetti = new ReferralConfetti(context);
        root.addView(mConfetti, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        root.setOnApplyWindowInsetsListener(
                (v, insets) -> {
                    android.graphics.Insets bars =
                            insets.getInsets(
                                    WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                    mStage.setPadding(bars.left, bars.top, bars.right, bars.bottom);
                    return WindowInsets.CONSUMED;
                });
        setContentView(root);
        prepareWindow();
        setCancelable(false);

        mModel =
                new FlowModel(
                        mRoot,
                        mSource,
                        mPreview,
                        new FlowModel.Host() {
                            @Override
                            public void render(ReferralScreen top, boolean forward) {
                                show(top, forward, true);
                            }

                            @Override
                            public void dismiss() {
                                ReferralFlowDialog.this.dismiss();
                            }
                        });
    }

    private void prepareWindow() {
        Window window = getWindow();
        if (window == null) return;
        window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
        window.setBackgroundDrawable(new ColorDrawable(mPalette.screen));
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false);
            WindowInsetsController controller = window.getInsetsController();
            if (controller != null) {
                int light =
                        WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                                | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                controller.setSystemBarsAppearance(mPalette.dark ? 0 : light, light);
            }
        }
        window.setNavigationBarContrastEnforced(false);
    }

    @Override
    protected void onStart() {
        super.onStart();
        mController.addListener(this);
    }

    @Override
    protected void onStop() {
        mController.removeListener(this);
        // ⚠️ L'intention de la jauge est celle du MOMENT (§ 12.20) : elle s'efface avec le flow.
        mController.setGaugeIntention(null);
        super.onStop();
    }

    /** Le statut arrive (ou change) : 4 et le cadeau ont besoin du code. */
    @Override
    public void onReferralChanged() {
        if (mModel == null || mRenderedWithStatus || mController.known() == null) return;
        show(mModel.top(), true, false);
    }

    @Override
    public void onBackPressed() {
        if (mModel == null) return;
        if (mModel.isTopLocked()) {
            // Une fenêtre qui attend une action ne se ferme que par elle (§ 12.14) : le pied
            // tressaille pour montrer où sont les sorties.
            if (mFooter != null && !ReferralUi.reduceMotion(getContext())) {
                mFooter.animate().cancel();
                mFooter.setTranslationX(0);
                float d = ReferralUi.dp(getContext(), 6);
                mFooter.animate()
                        .translationX(d)
                        .setDuration(60)
                        .withEndAction(
                                () ->
                                        mFooter.animate()
                                                .translationX(-d)
                                                .setDuration(80)
                                                .withEndAction(
                                                        () ->
                                                                mFooter.animate()
                                                                        .translationX(0)
                                                                        .setDuration(60)))
                        .start();
            }
            return;
        }
        mModel.back();
    }

    // -------------------- Le dessin --------------------

    /** Remplace la fenêtre affichée. {@code animate} : une vraie navigation (pas un rafraîchissement). */
    private void show(ReferralScreen screen, boolean forward, boolean animate) {
        if (mStage == null) return;
        mRenderedWithStatus = mController.known() != null;
        View next = build(screen);
        View previous = mCurrent;
        mCurrent = next;
        mStage.addView(next, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        if (previous != null) mStage.removeView(previous);
        if (animate && previous != null && !ReferralUi.reduceMotion(getContext())) {
            // Un écran ouvert par-dessus entre par la fin, le retour par le début — miroir en RTL.
            boolean rtl = mStage.getLayoutDirection() == View.LAYOUT_DIRECTION_RTL;
            float sign = (forward ? 1 : -1) * (rtl ? -1 : 1);
            next.setTranslationX(sign * ReferralUi.dp(getContext(), 48));
            next.setAlpha(0f);
            next.animate()
                    .translationX(0)
                    .alpha(1f)
                    .setDuration(260)
                    .setInterpolator(ReferralUi.EASE_OUT)
                    .start();
        }
    }

    /** Relit l'écran du dessus sans navigation (une formule choisie, un bouton qui change). */
    private void refreshTop() {
        if (mModel != null) show(mModel.top(), true, false);
    }

    private void celebrate() {
        if (mConfetti != null) {
            mConfetti.fire();
            ReferralUi.success(mConfetti);
        }
    }

    private void action(String screen, String action) {
        mController.note("paywall_action", mPreview, "screen", screen, "action", action);
    }

    private String s(String key) {
        return ReferralStrings.get(getContext(), key);
    }

    private View build(ReferralScreen screen) {
        switch (screen.kind) {
            case WELCOME:
                return welcome();
            case ANNOUNCE:
                return announce();
            case PAUSED:
                return paused(screen.chosen);
            case SUPPORT:
                return support(screen.locked);
            case INVITE:
                return invite(screen.shared);
            case BILLING:
                return billing();
            case GIFT:
                return gift(screen);
            default:
                // Les feuilles (1, 3, 8, 8 bis) ne passent jamais par ici.
                return new View(getContext());
        }
    }

    // -------------------- Le gabarit --------------------

    private View shell(
            @Nullable String eyebrow,
            @Nullable Runnable onBack,
            @Nullable Runnable onClose,
            List<View> content,
            List<View> footer) {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        LinearLayout page = ReferralUi.column(context);
        page.setBackgroundColor(p.screen);

        // La barre du haut — 🔴 § 12.38 : un fond, même invisible.
        FrameLayout bar = new FrameLayout(context);
        bar.setBackgroundColor(p.screen);
        int barPad = ReferralUi.dp(context, 8);
        bar.setPadding(barPad, 0, barPad, 0);
        if (eyebrow != null) {
            TextView label = ReferralUi.text(context, eyebrow, 14, ReferralUi.SEMIBOLD, p.text2);
            label.setSingleLine(true);
            bar.addView(label, ReferralUi.frame(ReferralUi.WRAP, ReferralUi.WRAP, Gravity.CENTER));
        }
        int hit = ReferralUi.dp(context, 44);
        if (onBack != null) {
            ImageView back = barButton(R.drawable.browther_intro_glyph_chevron_left, 18, s("invite.back"));
            back.getDrawable().setAutoMirrored(true);
            back.setOnClickListener(v -> onBack.run());
            bar.addView(back, ReferralUi.frame(hit, hit, Gravity.START | Gravity.CENTER_VERTICAL));
        }
        if (onClose != null) {
            ImageView close = barButton(R.drawable.browther_intro_glyph_xmark, 16, s("common.close"));
            close.setOnClickListener(v -> onClose.run());
            bar.addView(close, ReferralUi.frame(hit, hit, Gravity.END | Gravity.CENTER_VERTICAL));
        }
        page.addView(bar, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 48)));

        // ⚠️ Au moins la hauteur disponible (contenu centré), jamais au plus : un contenu plus
        // haut défile au lieu d'être rogné.
        ScrollView scroll = new ScrollView(context);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(p.screen);
        scroll.setClipToPadding(false);
        FrameLayout centerer = new FrameLayout(context);
        centerer.setBackgroundColor(p.screen);
        LinearLayout column = ReferralUi.column(context);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        int padH = ReferralUi.dp(context, 20);
        int padV = ReferralUi.dp(context, 12);
        column.setPadding(padH, padV, padH, padV);
        boolean first = true;
        for (View view : content) {
            if (!first) ReferralUi.gap(column, 18);
            first = false;
            if (view.getLayoutParams() == null) {
                view.setLayoutParams(ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
            }
            column.addView(view);
        }
        FrameLayout.LayoutParams columnParams =
                new FrameLayout.LayoutParams(
                        ReferralUi.MATCH, ReferralUi.WRAP, Gravity.CENTER);
        centerer.addView(column, columnParams);
        capWidth(column);
        scroll.addView(centerer, new ScrollView.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        page.addView(scroll, new LinearLayout.LayoutParams(ReferralUi.MATCH, 0, 1));

        LinearLayout foot = ReferralUi.column(context);
        foot.setGravity(Gravity.CENTER_HORIZONTAL);
        foot.setBackgroundColor(p.screen);
        foot.setPadding(padH, ReferralUi.dp(context, 10), padH, ReferralUi.dp(context, 8));
        first = true;
        for (View view : footer) {
            if (!first) ReferralUi.gap(foot, 6);
            first = false;
            foot.addView(view);
        }
        capWidth(foot);
        FrameLayout footHolder = new FrameLayout(context);
        footHolder.setBackgroundColor(p.screen);
        footHolder.addView(
                foot,
                new FrameLayout.LayoutParams(
                        ReferralUi.MATCH, ReferralUi.WRAP, Gravity.CENTER_HORIZONTAL));
        page.addView(footHolder, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        mFooter = foot;
        return page;
    }

    /** Plafond de largeur (tablette, paysage) : 560 dp, centré. */
    private void capWidth(View view) {
        int max = ReferralUi.dp(getContext(), MAX_WIDTH_DP);
        view.addOnLayoutChangeListener(
                (v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
                    ViewGroup.LayoutParams params = v.getLayoutParams();
                    ViewGroup parent = (ViewGroup) v.getParent();
                    if (parent == null) return;
                    int wanted = parent.getWidth() > max ? max : ReferralUi.MATCH;
                    if (params.width != wanted) {
                        params.width = wanted;
                        v.post(v::requestLayout);
                    }
                });
    }

    private ImageView barButton(int drawable, float sizeDp, String description) {
        Context context = getContext();
        ImageView button = ReferralUi.glyph(context, drawable, sizeDp, mPalette.text2);
        int pad = (ReferralUi.dp(context, 44) - ReferralUi.dp(context, sizeDp)) / 2;
        button.setPadding(pad, pad, pad, pad);
        button.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        button.setContentDescription(description);
        button.setBackground(
                ReferralUi.pressable(null, ReferralUi.withAlpha(mPalette.text, 0.1f), ReferralUi.dp(context, 22)));
        return button;
    }

    private static List<View> list(View... views) {
        List<View> out = new ArrayList<>();
        for (View view : views) if (view != null) out.add(view);
        return out;
    }

    private void dismissFlow() {
        if (mModel != null) mModel.dismiss();
    }

    // -------------------- O — en aperçu de recette --------------------

    private View welcome() {
        Context context = getContext();
        View entry = new ReferralCodeEntry(context, "manual", mPreview, this::celebrate);
        return shell(
                null,
                null,
                null,
                list(entry),
                list(ReferralUi.textExit(context, mPalette, s("welcome.later"), false, false, this::dismissFlow)));
    }

    // -------------------- 0 — l'annonce --------------------

    private View announce() {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        return shell(
                null,
                null,
                null,
                list(
                        ReferralUi.roundIcon(context, p, R.drawable.browther_referral_glyph_heart, ReferralUi.Tone.GOLD, 64),
                        ReferralUi.title(context, p, s("announce.title")),
                        ReferralUi.body(context, p, s("announce.body")),
                        ReferralUi.featureList(context, p, ExtrasState.offered(), false)),
                list(
                        ReferralUi.primaryButton(
                                context,
                                p,
                                s("announce.invite"),
                                s("announce.inviteSub"),
                                0,
                                () -> {
                                    action("announce", "invite");
                                    // « Inviter un proche » mène à l'écran Parrainage (§ 12.15).
                                    dismissFlow();
                                    BrowtherReferralPresenter.presentHome(mActivity, Source.FLOW);
                                }),
                        ReferralUi.textExit(
                                context,
                                p,
                                s("announce.later"),
                                false,
                                false,
                                () -> {
                                    action("announce", "later");
                                    dismissFlow();
                                    // ⭐ Écran 0 bis : un TOAST, ⛔ pas une seconde fenêtre (§ 12.9).
                                    mHandler.postDelayed(
                                            () -> mController.announceLaterToast(mActivity), 350);
                                })));
    }

    // -------------------- 2 — J0 --------------------

    /**
     * {@code chosen} = ouvert par la personne elle-même (le « Débloquer » du panneau). ⭐ Alors la
     * fenêtre se ferme normalement, et ce qu'elle ouvre aussi : « une fenêtre qu'on pouvait fermer
     * n'en ouvre pas une qu'on ne peut plus fermer » (§ 12.16). Tombé tout seul, J0 reste verrouillé
     * — la sortie est sur les trois façons.
     */
    private View paused(boolean chosen) {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        List<View> footer =
                list(
                        ReferralUi.primaryButton(
                                context,
                                p,
                                s("locked.cta"),
                                s("ending.supportSub"),
                                R.drawable.browther_referral_glyph_heart,
                                () -> {
                                    action("paused", "support");
                                    // 🔴 Depuis un J0 TOMBÉ, les trois façons forment un circuit
                                    // FERMÉ (§ 12.16) ; depuis un J0 OUVERT par la personne, elles
                                    // se ferment comme elle a pu fermer celui-ci.
                                    if (mModel != null) mModel.replaceTop(ReferralScreen.support(!chosen));
                                }));
        // ⛔ Pas de « plus tard » : la sortie est sur les trois façons. ⚠️ La cadence ne se
        // raconte qu'au J0 qui TOMBE : ouvert d'un « Débloquer », il ne « reviendra » pas.
        if (!chosen) {
            TextView foot = ReferralUi.footnote(context, p, s("paused.foot"));
            foot.setTextColor(p.text3);
            foot.setPadding(0, ReferralUi.dp(context, 4), 0, 0);
            footer.add(foot);
        }
        return shell(
                null,
                null,
                chosen ? this::dismissFlow : null,
                // L'icône DIT l'état, ⛔ elle ne réchauffe pas (recette iOS, 2026-09-24).
                list(
                        ReferralUi.roundIcon(context, p, R.drawable.browther_intro_glyph_pause, ReferralUi.Tone.GOLD, 64),
                        ReferralUi.title(context, p, s("paused.title")),
                        ReferralUi.body(context, p, s("paused.body")),
                        ReferralUi.featureList(context, p, ExtrasState.paused(), false)),
                footer);
    }

    // -------------------- 2b — les trois façons --------------------

    private View support(boolean locked) {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        ReferralStatus known = mController.known();
        ReferralGaugeView gauge =
                new ReferralGaugeView(
                        context, ReferralGaugeView.Mode.TOY, known != null, mPreview, this::celebrate);
        gauge.bind(known == null ? 0 : known.milestones.validated, mController.scale());

        // ⭐ Le bouton REPREND le nombre de la jauge (§ 12.30), cran par cran ; au palier « à vie »
        // il s'allume — mêmes cotes, donc le pied de l'écran ne saute pas.
        FrameLayout inviteSlot = new FrameLayout(context);
        inviteSlot.setLayoutParams(ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        Runnable fillInvite =
                () -> {
                    inviteSlot.removeAllViews();
                    inviteSlot.addView(inviteButton(), new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));
                };
        fillInvite.run();
        gauge.setOnIntentionChanged(fillInvite);

        List<View> footer = list(inviteSlot);
        if (mController.billingAvailable()) {
            footer.add(ReferralUi.orSeparator(context, p, s("support.or")));
            footer.add(
                    ReferralUi.secondaryButton(
                            context,
                            p,
                            ReferralStrings.fill(s("support.money"), "price", ReferralPricing.monthly),
                            () -> {
                                action("support", "billing");
                                if (mModel != null) mModel.push(ReferralScreen.billing());
                            }));
        }
        // La sortie : une phrase que la personne dit d'elle-même — ⛔ elle n'accorde rien.
        footer.add(
                ReferralUi.textExit(
                        context,
                        p,
                        s("support.none"),
                        true,
                        false,
                        () -> {
                            action("support", "dua");
                            mController.closeCircuit(mPreview);
                            dismissFlow();
                        }));
        return shell(
                s("locked.cta"),
                null,
                // Ouverte par la personne (toast, rappel) : elle se ferme normalement ; depuis J0,
                // circuit fermé (§ 12.16).
                locked ? null : this::dismissFlow,
                list(ReferralUi.title(context, p, s("support.title")), gauge),
                footer);
    }

    private View inviteButton() {
        Context context = getContext();
        MilestoneScale scale = mController.scale();
        Integer stored = mController.gaugeIntention();
        int intention = stored == null ? 0 : stored;
        String label =
                intention > 1
                        ? ReferralStrings.plural(context, "support.inviteCount", intention)
                        : s("announce.invite");
        String sub =
                ReferralStrings.plural(
                        context, "support.inviteSub", ReferralProduct.validationTargetDays);
        Runnable open =
                () -> {
                    action("support", "invite");
                    if (mModel != null) mModel.push(ReferralScreen.invite(false));
                };
        return intention >= scale.lifetimeAt
                ? ReferralUi.lifetimeButton(context, mPalette, label, sub, open)
                : ReferralUi.primaryButton(context, mPalette, label, sub, 0, open);
    }

    // -------------------- 4 — inviter --------------------

    private View invite(boolean shared) {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        int depth = mModel == null ? 1 : mModel.depth();
        boolean inCircuit = depth > 1 && !shared;
        ReferralStatus known = mController.known();
        ReferralGaugeView gauge =
                new ReferralGaugeView(
                        context, ReferralGaugeView.Mode.TOY, known != null, mPreview, this::celebrate);
        gauge.bind(known == null ? 0 : known.milestones.validated, mController.scale());
        List<View> content = list(gauge);
        // ⚠️ La carte du code se place ENTRE la jauge (carte « À vie ») et le bouton de partage :
        // on partage le code, les deux doivent se toucher (§ 12.20).
        if (known != null) {
            content.add(
                    new ReferralCodeCard(
                            context,
                            known,
                            () -> {
                                // ⭐ Copier EST un partage abouti (§ 12.20) — 3 jours offerts compris.
                                mController.note(
                                        "referral_shared", mPreview, "screen", "invite", "result", "copied");
                                if (mModel != null) mModel.replaceTop(ReferralScreen.invite(true));
                                mController.shareDone("invite", mPreview);
                            }));
        }
        content.add(
                ReferralUi.footnote(
                        context,
                        p,
                        ReferralStrings.plural(
                                context, "invite.foot", ReferralProduct.validationTargetDays)));

        List<View> footer = new ArrayList<>();
        if (known != null) {
            footer.add(
                    ReferralUi.primaryButton(
                            context,
                            p,
                            s("invite.share"),
                            null,
                            R.drawable.browther_referral_glyph_share,
                            () ->
                                    ReferralSharing.share(
                                            mActivity,
                                            known,
                                            "invite",
                                            mPreview,
                                            // ⭐ Un partage abouti LIBÈRE l'écran 4 (§ 12.16).
                                            result -> {
                                                if (mModel != null) {
                                                    mModel.replaceTop(ReferralScreen.invite(true));
                                                }
                                            })));
        }
        footer.add(
                ReferralUi.textExit(
                        context,
                        p,
                        shared ? s("invite.closeAfterShare") : s("invite.back"),
                        false,
                        !shared,
                        () -> {
                            if (shared || !inCircuit) {
                                dismissFlow();
                            } else if (mModel != null) {
                                mModel.back();
                            }
                        }));
        return shell(
                s("invite.eyebrow"),
                inCircuit && mModel != null ? mModel::back : null,
                inCircuit ? null : this::dismissFlow,
                content,
                footer);
    }

    // -------------------- 7 — soutenir financièrement (porte factice) --------------------

    private boolean mGifting;
    private @Nullable String mBillingError;

    private View billing() {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        int depth = mModel == null ? 1 : mModel.depth();
        boolean inCircuit = depth > 1;
        LinearLayout plans = ReferralUi.column(context);
        plans.addView(
                plan(
                        BillingPeriod.YEARLY,
                        s("billing.year"),
                        s("billing.yearBadge"),
                        ReferralPricing.yearly,
                        ReferralPricing.yearlyStruck,
                        ReferralStrings.fill(s("billing.yearSub"), "price", ReferralPricing.yearlyPerMonth)),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        plans.addView(
                plan(
                        BillingPeriod.MONTHLY,
                        s("billing.month"),
                        null,
                        ReferralPricing.monthly,
                        null,
                        s("billing.monthSub")),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 10)));

        TextView title = ReferralUi.title(context, p, s("billing.title"));
        List<View> content =
                list(
                        title,
                        ReferralUi.body(context, p, s("billing.body")),
                        ReferralUi.featureList(context, p, ExtrasState.included(), true),
                        plans);
        // ⛔ Ni « Restaurer mes achats » (rien à restaurer), ni texte légal d'Apple : sur Android
        // rien n'est débité (§ 12.27).

        BillingPeriod period = mController.period();
        String label =
                period == BillingPeriod.YEARLY
                        ? ReferralStrings.fill(s("billing.ctaYear"), "price", ReferralPricing.yearly)
                        : ReferralStrings.fill(s("billing.ctaMonth"), "price", ReferralPricing.monthly);
        View cta = ReferralUi.primaryButton(context, p, label, null, 0, this::gift);
        cta.setEnabled(!mGifting);
        cta.setAlpha(mGifting ? 0.6f : 1f);
        List<View> footer = list(cta);
        if (mBillingError != null) {
            TextView error = ReferralUi.footnote(context, p, mBillingError);
            error.setPadding(0, ReferralUi.dp(context, 6), 0, 0);
            footer.add(error);
        }
        footer.add(
                ReferralUi.textExit(
                        context,
                        p,
                        s("invite.back"),
                        false,
                        true,
                        () -> {
                            if (inCircuit && mModel != null) {
                                mModel.back();
                            } else {
                                dismissFlow();
                            }
                        }));
        return shell(
                s("billing.eyebrow"),
                inCircuit && mModel != null ? mModel::back : null,
                inCircuit ? null : this::dismissFlow,
                content,
                footer);
    }

    /** Une formule. Sélectionnée = la surface verte du parrainage + un bouton radio plein. */
    private View plan(
            BillingPeriod period,
            String title,
            @Nullable String badge,
            String price,
            @Nullable String struck,
            String sub) {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        boolean selected = mController.period() == period;
        LinearLayout row = ReferralUi.row(context);
        int pad = ReferralUi.dp(context, 14);
        row.setPadding(pad, pad, pad, pad);
        float radius = ReferralUi.dp(context, 16);
        row.setBackground(
                ReferralUi.pressable(
                        ReferralUi.rounded(
                                selected ? p.greenSurface : p.panel,
                                radius,
                                ReferralUi.dp(context, selected ? 1.5f : 1),
                                selected ? p.green : p.line),
                        ReferralUi.withAlpha(p.text, 0.08f),
                        radius));

        View radio = radio(selected);
        LinearLayout.LayoutParams radioParams =
                new LinearLayout.LayoutParams(ReferralUi.dp(context, 20), ReferralUi.dp(context, 20));
        radioParams.setMarginEnd(ReferralUi.dp(context, 12));
        row.addView(radio, radioParams);

        LinearLayout texts = ReferralUi.column(context);
        LinearLayout head = ReferralUi.row(context);
        head.addView(ReferralUi.text(context, title, 17, ReferralUi.SEMIBOLD, p.text));
        if (badge != null) {
            TextView pill = ReferralUi.text(context, badge, 12, ReferralUi.SEMIBOLD, 0xFFFFFFFF);
            int ph = ReferralUi.dp(context, 8);
            pill.setPadding(ph, ReferralUi.dp(context, 2), ph, ReferralUi.dp(context, 2));
            pill.setBackground(ReferralUi.rounded(p.greenFill, ReferralUi.dp(context, 100)));
            LinearLayout.LayoutParams pillParams =
                    new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
            pillParams.setMarginStart(ReferralUi.dp(context, 8));
            head.addView(pill, pillParams);
        }
        texts.addView(head);
        TextView subView = ReferralUi.text(context, sub, 13, ReferralUi.REGULAR, p.text2);
        subView.setPadding(0, ReferralUi.dp(context, 3), 0, 0);
        texts.addView(subView);
        row.addView(texts, new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1));

        LinearLayout prices = ReferralUi.column(context);
        prices.setGravity(Gravity.END);
        if (struck != null) {
            TextView struckView = ReferralUi.text(context, struck, 13, ReferralUi.REGULAR, p.text2);
            struckView.setPaintFlags(struckView.getPaintFlags() | Paint.STRIKE_THRU_TEXT_FLAG);
            prices.addView(struckView);
        }
        TextView priceView = ReferralUi.text(context, price, 17, ReferralUi.SEMIBOLD, p.text);
        priceView.setFontFeatureSettings("tnum");
        prices.addView(priceView);
        LinearLayout.LayoutParams pricesParams =
                new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
        pricesParams.setMarginStart(ReferralUi.dp(context, 8));
        row.addView(prices, pricesParams);

        row.setClickable(true);
        row.setSelected(selected);
        row.setContentDescription(title + ", " + price + (badge == null ? "" : ", " + badge));
        row.setOnClickListener(
                v -> {
                    ReferralUi.tick(v);
                    mController.setPeriod(period);
                    refreshTop();
                });
        return row;
    }

    private View radio(boolean selected) {
        Context context = getContext();
        FrameLayout ring = new FrameLayout(context);
        android.graphics.drawable.GradientDrawable outline =
                new android.graphics.drawable.GradientDrawable();
        outline.setShape(android.graphics.drawable.GradientDrawable.OVAL);
        outline.setStroke(ReferralUi.dp(context, 2), selected ? mPalette.green : mPalette.text2);
        ring.setBackground(outline);
        if (selected) {
            View dot = new View(context);
            dot.setBackground(ReferralUi.oval(mPalette.green));
            int size = ReferralUi.dp(context, 10);
            ring.addView(dot, ReferralUi.frame(size, size, Gravity.CENTER));
        }
        return ring;
    }

    /**
     * 🔴 Au toucher de « Je soutiens · … » : la vérité, TOUT DE SUITE (§ 12.27) — le service offre
     * un mois (une fois par sujet) et « C'est cadeau ! » s'ouvre. ⭐ Payer est une des trois
     * sorties : « cadeau », ⛔ jamais la fenêtre d'où l'on est parti (§ 12.17).
     */
    private void gift() {
        if (mGifting) return;
        mGifting = true;
        mBillingError = null;
        refreshTop();
        mController.gift(
                mController.period(),
                mPreview,
                outcome -> {
                    mGifting = false;
                    if (!isShowing() || mModel == null) return;
                    if (outcome == null) {
                        mBillingError = s("billing.failed");
                        refreshTop();
                        return;
                    }
                    mGiftCelebrated = false;
                    mModel.replaceAll(
                            ReferralScreen.gift(outcome.granted, outcome.coveredUntil),
                            Source.PURCHASE);
                });
    }

    // -------------------- 7 ter — « C'est cadeau ! » --------------------

    /**
     * La porte factice, au bout du chemin (§ 12.27) : 🔴 confettis + haptique de succès pour que la
     * personne comprenne d'un coup d'œil que c'est un cadeau et que tout lui est ouvert, « le
     * paiement arrive bientôt sur Android », la date de fin, la liste, puis la DEMANDE : partager
     * l'app. Déjà offert : le même écran, sans confettis ni promesse, avec la même demande.
     */
    private View gift(ReferralScreen screen) {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        List<View> content =
                list(
                        ReferralUi.roundIcon(context, p, R.drawable.browther_referral_glyph_gift, ReferralUi.Tone.GREEN, 64),
                        ReferralUi.title(context, p, s(screen.granted ? "gift.title" : "gift.titleAgain")),
                        ReferralUi.body(context, p, s(screen.granted ? "gift.body" : "gift.bodyAgain")));
        Instant until = ReferralDate.parse(screen.until);
        if (screen.granted && until != null) {
            TextView untilView =
                    ReferralUi.text(
                            context,
                            ReferralStrings.fill(
                                    s("gift.until"), "date", ReferralFormat.date(context, until, true)),
                            16,
                            ReferralUi.SEMIBOLD,
                            p.green);
            untilView.setGravity(Gravity.CENTER_HORIZONTAL);
            content.add(untilView);
        }
        if (screen.granted) {
            content.add(ReferralUi.featureList(context, p, ExtrasState.offered(), true));
        }
        TextView ask = ReferralUi.text(context, s("gift.ask"), 15, ReferralUi.MEDIUM, p.text);
        int pad = ReferralUi.dp(context, 14);
        ask.setPadding(pad, pad, pad, pad);
        ask.setBackground(ReferralUi.rounded(p.goldSurface, ReferralUi.dp(context, 14)));
        content.add(ask);

        List<View> footer = new ArrayList<>();
        ReferralStatus known = mController.known();
        if (known != null) {
            footer.add(
                    ReferralUi.primaryButton(
                            context,
                            p,
                            s("invite.share"),
                            null,
                            R.drawable.browther_referral_glyph_share,
                            () -> ReferralSharing.share(mActivity, known, "gift", mPreview, null)));
        }
        footer.add(
                ReferralUi.textExit(
                        context, p, s("invite.closeAfterShare"), false, false, this::dismissFlow));

        if (screen.granted && !mGiftCelebrated) {
            mGiftCelebrated = true;
            mHandler.postDelayed(this::celebrate, 200);
        }
        return shell(null, null, this::dismissFlow, content, footer);
    }
}
