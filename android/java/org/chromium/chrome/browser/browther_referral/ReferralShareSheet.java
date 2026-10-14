/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.annotation.Nullable;

import com.google.android.material.bottomsheet.BottomSheetBehavior;
import com.google.android.material.bottomsheet.BottomSheetDialog;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.MilestoneScale;
import org.chromium.chrome.browser.browther_referral.core.ReferralShare;
import org.chromium.chrome.browser.browther_referral.core.ReferralSharePrompt;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideo;

import java.io.File;
import java.lang.ref.WeakReference;
import java.util.Locale;

/**
 * La feuille <b>« Partager mon code »</b> : deux onglets, <b>Statut WhatsApp</b> puis <b>Message</b>
 * — private/docs/PARRAINAGE.md § 11, port de {@code ReferralShareSheet} (iOS, la référence ;
 * elle-même portée de Fajrunaa, recettée sur iPhone par Karim le 2026-10-08).
 *
 * <p>⭐ <b>UN bouton sur l'écran ({@link #button}), et le statut en PREMIER onglet</b> (choix D de
 * Karim sur maquette) : c'est le partage qui touche le plus de monde ; il était « un peu caché »
 * derrière un second bouton en contour. Ouvert par défaut, il reçoit tout le trafic du bouton
 * principal sans forcer personne. ⛔ L'ordre des onglets n'est pas cosmétique : ne pas remettre le
 * message devant. ⛔ Plus de second bouton « Publier en statut WhatsApp » sur les écrans.
 *
 * <p>🔴 <b>Rien ici ne retient le geste d'avant</b> : pas de vidéo (réseau, vidéo coupée, absente
 * dans la langue, pas arrivée en {@code WAIT_MS}) ⇒ l'onglet Statut redevient l'image seule dans un
 * grand cadre, l'onglet Message envoie l'image, sans case à cocher. ⛔ Aucun bouton ne dépend de la
 * vidéo.
 *
 * <p>⭐ <b>Les 3 jours du moment « partage » se disent UNE fois, quand la feuille se referme</b>
 * ({@link #report}) — pas entre les deux envois, sous WhatsApp. Refermée après un envoi sur deux :
 * le partage a abouti quand même. Sur l'écran 4 du circuit, c'est aussi là qu'il passe à son état
 * « partagé » ({@code onAchieved}).
 *
 * <p>⚠️ Un seul onglet est monté à la fois : chacun a son lecteur vidéo. Leur état (ce qui est
 * coché, ce qui est parti), lui, survit au changement d'onglet.
 *
 * <p>⭐ <b>Le partage proposé</b> (2026-10-14, {@code devndin/docs/PARRAINAGE.md} § 12.45) est CETTE
 * feuille, ouverte d'elle-même ({@link #openPrompt}) : origine {@code share_prompt}, onglet
 * d'arrivée choisi par la règle, un titre au-dessus des onglets (le compteur ou « Browther t'est
 * utile ? », puis la phrase du gain ou celle de l'abonné) et ses sorties (« Plus tard », et « Ne
 * plus me redemander » pour qui a payé). ⛔ Jamais une seconde feuille écrite à côté.
 *
 * <p>⚠️ Ce qu'Android ne dit pas : la fin d'un envoi. « Occupé » dure donc du toucher du bouton au
 * RETOUR dans la feuille (sa fenêtre perd le focus, puis le retrouve) — {@link #beginSend}.
 */
public final class ReferralShareSheet extends BottomSheetDialog {
    /** Un envoi qui n'a pas pu partir se dit le temps d'être lu, puis s'efface. */
    static final long FAILURE_TOAST_MS = 6_000;

    /**
     * Si rien n'a pris le focus après un envoi (l'app visée ne s'est pas montrée), la feuille se
     * rend au bout de ce délai : ⛔ jamais un bouton qui tourne sans fin.
     */
    private static final long SEND_TIMEOUT_MS = 4_000;

    private static final int MAX_WIDTH_DP = 520;
    private static final int SIDE_DP = 20;

    private enum Tab {
        STATUS,
        MESSAGE
    }

    /** Ce qui fait de la feuille le PARTAGE PROPOSÉ : son profil, son onglet, son compteur. */
    public static final class Prompt {
        public final ReferralSharePrompt.Profile profile;
        public final ReferralSharePrompt.Tab openedOn;
        public final ReferralSharePrompt.Headline headline;

        public Prompt(
                ReferralSharePrompt.Profile profile,
                ReferralSharePrompt.Tab openedOn,
                ReferralSharePrompt.Headline headline) {
            this.profile = profile;
            this.openedOn = openedOn;
            this.headline = headline;
        }
    }

    /** Comment le partage proposé s'est refermé — la valeur de {@code paywall_action.action}. */
    public enum PromptExit {
        /** « Plus tard ». */
        LATER("later"),
        /** « Ne plus me redemander » (abonné, accès à vie). */
        MUTE("mute"),
        /** La croix, le glissé, le retour système. */
        DISMISS("dismiss");

        public final String wire;

        PromptExit(String wire) {
            this.wire = wire;
        }
    }

    /** La feuille ouverte : deux touchers rapides sur le bouton n'en ouvrent pas deux. */
    private static @Nullable WeakReference<ReferralShareSheet> sOpen;

    private final Activity mActivity;
    private final ReferralStatus mStatus;
    private final String mOrigin;
    private final boolean mPreview;
    private final @Nullable Runnable mOnAchieved;
    /** {@code null} = « Partager mon code » ; sinon le partage proposé. */
    private final @Nullable Prompt mPrompt;
    /** La sortie choisie par un bouton du partage proposé, dite à la fermeture. */
    private @Nullable PromptExit mPromptExit;
    private final ReferralUi.Palette mP;
    private final ReferralStatusImage.Texts mTexts;
    private final String mCode;
    private final String mLink;
    private final ReferralStatusVideoStore.Watch mVideo = new ReferralStatusVideoStore.Watch();
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final ReferralShareStatusTab mStatusTab;
    private final ReferralShareMessageTab mMessageTab;
    private final LinearLayout mTabs;
    private final FrameLayout mContent;
    private final LinearLayout mFooter;

    private Tab mTab;
    private @Nullable Bitmap mImage;
    private @Nullable File mImageFile;
    /** Au moins un envoi a abouti. */
    private boolean mAchieved;
    private boolean mReported;
    private boolean mFocused;
    /** Un envoi est parti, et l'on n'en est pas revenu. */
    private boolean mBusy;
    /** Depuis cet envoi, la fenêtre a bien perdu le focus (on est parti dans une autre app). */
    private boolean mLeft;

    /**
     * ⭐ Le bouton « Partager mon code », qui porte sa feuille — pendant de {@code
     * ReferralShareButton} (iOS). Il fait la même chose partout où il est posé : onglet Inviter,
     * onglet Invitations, écran 4 du circuit.
     *
     * <p>🔴 Partager ne crée AUCUNE invitation : un partage abouti n'ouvre droit qu'aux 3 jours (§
     * 4). ⭐ La vidéo est demandée dès que le bouton est à l'écran, pas au tap : elle est là quand
     * la feuille s'ouvre ({@link ReferralStatusVideoStore}).
     *
     * @param origin d'où part le partage ({@code home}, {@code invite}) — la valeur de {@code
     *     screen} dans {@code referral_shared}.
     * @param preview un aperçu de recette : ⛔ rien ne s'écrit (§ 13.8).
     * @param onAchieved appelé une fois, à la fermeture de la feuille, si un envoi a abouti.
     */
    public static View button(
            Context context,
            Activity activity,
            ReferralUi.Palette p,
            ReferralStatus status,
            String origin,
            boolean preview,
            @Nullable Runnable onAchieved) {
        View button =
                ReferralUi.primaryButton(
                        context,
                        p,
                        ReferralStrings.get(context, "invite.share"),
                        null,
                        R.drawable.browther_referral_glyph_share,
                        () -> open(activity, status, origin, preview, onAchieved));
        button.addOnAttachStateChangeListener(
                new View.OnAttachStateChangeListener() {
                    @Override
                    public void onViewAttachedToWindow(View view) {
                        ReferralStatusVideoStore.warmUp(view.getContext());
                    }

                    @Override
                    public void onViewDetachedFromWindow(View view) {}
                });
        return button;
    }

    /** Ouvre la feuille — une seule à la fois. */
    public static void open(
            Activity activity,
            ReferralStatus status,
            String origin,
            boolean preview,
            @Nullable Runnable onAchieved) {
        if (activity.isFinishing() || activity.isDestroyed()) return;
        ReferralShareSheet open = sOpen == null ? null : sOpen.get();
        if (open != null && open.isShowing()) return;
        ReferralShareSheet sheet =
                new ReferralShareSheet(activity, status, origin, preview, onAchieved, null);
        sOpen = new WeakReference<>(sheet);
        sheet.show();
    }

    /** Une feuille de partage est-elle déjà à l'écran ? (⛔ jamais deux feuilles, § 3.4.) */
    public static boolean isOpen() {
        ReferralShareSheet open = sOpen == null ? null : sOpen.get();
        return open != null && open.isShowing();
    }

    /**
     * ⭐ <b>Le partage proposé</b> : la MÊME feuille, ouverte d'elle-même, origine {@code
     * share_prompt}. {@code false} = rien ne s'est ouvert (une feuille est déjà là, l'activité
     * part). Le contrôleur écrit l'affichage APRÈS (⛔ jamais avant d'avoir réellement ouvert).
     */
    public static boolean openPrompt(
            Activity activity, ReferralStatus status, Prompt prompt, boolean preview) {
        if (activity.isFinishing() || activity.isDestroyed() || isOpen()) return false;
        ReferralShareSheet sheet =
                new ReferralShareSheet(activity, status, SHARE_PROMPT, preview, null, prompt);
        sOpen = new WeakReference<>(sheet);
        sheet.show();
        return true;
    }

    /** L'origine du partage proposé — la valeur de {@code screen} partout (§ 12.45). */
    public static final String SHARE_PROMPT = "share_prompt";

    private ReferralShareSheet(
            Activity activity,
            ReferralStatus status,
            String origin,
            boolean preview,
            @Nullable Runnable onAchieved,
            @Nullable Prompt prompt) {
        super(activity);
        mActivity = activity;
        mStatus = status;
        mOrigin = origin;
        mPreview = preview;
        mOnAchieved = onAchieved;
        mPrompt = prompt;
        // ⭐ L'onglet d'arrivée : le statut pour « Partager mon code » (choix D de Karim) ; celui de
        // la règle pour le partage proposé (il alterne, et c'est « Message » sans WhatsApp).
        mTab =
                prompt != null && prompt.openedOn == ReferralSharePrompt.Tab.MESSAGE
                        ? Tab.MESSAGE
                        : Tab.STATUS;
        mP = ReferralUi.palette(activity);
        // 🔴 La langue de l'image, de la vidéo et du message joint = celle de l'app (on parle à SES
        // contacts) : fr, en ou ar, sinon l'anglais.
        mTexts = ReferralStatusImage.Texts.current(activity, new MilestoneScale(status).lifetimeAt);
        mCode = status.referral.code.toUpperCase(Locale.ROOT);
        mLink = ReferralShare.link(mCode, status.referral.url);
        mStatusTab = new ReferralShareStatusTab(this, mP);
        mMessageTab = new ReferralShareMessageTab(this, mP);
        Context context = getContext();
        mTabs = ReferralUi.row(context);
        mContent = new FrameLayout(context);
        mFooter = ReferralUi.column(context);
        prepare();
        setContentView(build());
        mount();
    }

    /**
     * L'image est dessinée UNE fois, ici : l'aperçu des deux onglets et le fichier qui part sont la
     * même image (ce qu'on voit est ce qui part). La vidéo, elle, est déjà là si le bouton a eu le
     * temps de la faire venir — sinon on l'attend un peu, puis on s'en passe.
     */
    private void prepare() {
        try {
            mImage = ReferralStatusImage.render(mActivity, mCode, mTexts);
        } catch (RuntimeException e) {
            // Pas d'image : l'onglet Message enverra le message texte d'avant.
            mImage = null;
        }
        Bitmap image = mImage;
        if (image != null) {
            ReferralSharing.statusImageFile(
                    mActivity,
                    mCode,
                    image,
                    file -> {
                        mImageFile = file;
                        refresh();
                    });
        }
        mVideo.start(
                mActivity,
                ReferralStatusVideo.statusLanguage(mTexts.language),
                () -> {
                    // La vidéo arrive, ou l'on renonce à l'attendre : les vignettes changent.
                    if (isShowing()) mount();
                });
    }

    // -------------------- Ce que les onglets lisent --------------------

    Activity activity() {
        return mActivity;
    }

    ReferralStatus status() {
        return mStatus;
    }

    String origin() {
        return mOrigin;
    }

    boolean preview() {
        return mPreview;
    }

    /** {@code opened_on} du partage proposé (l'onglet où il s'est OUVERT), {@code null} ailleurs. */
    @Nullable
    String openedOn() {
        return mPrompt == null ? null : mPrompt.openedOn.wire;
    }

    ReferralStatusImage.Texts texts() {
        return mTexts;
    }

    String code() {
        return mCode;
    }

    String link() {
        return mLink;
    }

    @Nullable
    Bitmap image() {
        return mImage;
    }

    /** L'image écrite en JPEG — {@code null} tant qu'elle ne l'est pas (ou si l'écriture a échoué). */
    @Nullable
    File imageFile() {
        return mImageFile;
    }

    ReferralStatusVideoStore.Watch video() {
        return mVideo;
    }

    /** La largeur de ce qui s'affiche dans la feuille, marges retirées. */
    int contentWidth() {
        Context context = getContext();
        return Math.min(
                        context.getResources().getDisplayMetrics().widthPixels,
                        ReferralUi.dp(context, MAX_WIDTH_DP))
                - 2 * ReferralUi.dp(context, SIDE_DP);
    }

    /** La fenêtre de la feuille a le focus : on est DANS Browther, la feuille devant. */
    boolean focused() {
        return mFocused;
    }

    boolean busy() {
        return mBusy;
    }

    // -------------------- Ce que les onglets lui disent --------------------

    /**
     * Un envoi vient de partir (WhatsApp, ou le sélecteur du système). Android ne dira pas quand il
     * finit : « occupé » dure jusqu'au RETOUR dans la feuille — sa fenêtre perd le focus, puis le
     * retrouve. C'est aussi ce qui retient le décompte du second statut tant qu'on est ailleurs.
     */
    void beginSend() {
        mBusy = true;
        mLeft = !mFocused;
        mHandler.removeCallbacks(mSendTimeout);
        mHandler.postDelayed(mSendTimeout, SEND_TIMEOUT_MS);
        refresh();
    }

    private final Runnable mSendTimeout =
            () -> {
                // Rien n'a pris le focus : aucune app ne s'est montrée, on rend la main.
                if (mBusy && !mLeft) endSend();
            };

    private void endSend() {
        mBusy = false;
        mHandler.removeCallbacks(mSendTimeout);
        refresh();
    }

    /** Un envoi a abouti : les 3 jours se diront à la fermeture. */
    void onSent() {
        mAchieved = true;
    }

    /** Tout ce qui devait partir est parti : la feuille se referme. */
    void onFinished() {
        dismiss();
    }

    /** Relit l'onglet affiché (coches, bouton, décompte) sans rien reconstruire. */
    void refresh() {
        if (mTab == Tab.STATUS) {
            mStatusTab.sync();
        } else {
            mMessageTab.sync();
        }
    }

    // -------------------- La fenêtre --------------------

    @Override
    protected void onStart() {
        super.onStart();
        BottomSheetBehavior<FrameLayout> behavior = getBehavior();
        behavior.setSkipCollapsed(true);
        behavior.setState(BottomSheetBehavior.STATE_EXPANDED);
        // Le fond est celui de notre contenu (coins arrondis compris) : le conteneur de la
        // bibliothèque devient transparent. ⚠️ Par son NOM : Chromium ne génère pas
        // `com.google.android.material.R` (voir `ReferralSheetDialog`).
        int sheetId =
                getContext()
                        .getResources()
                        .getIdentifier("design_bottom_sheet", "id", getContext().getPackageName());
        View sheet = sheetId == 0 ? null : findViewById(sheetId);
        if (sheet != null) sheet.setBackgroundColor(Color.TRANSPARENT);
        // Une feuille : son bouton est en bas, les toasts montent (`ReferralToastPlacement`).
        BrowtherReferralPresenter.sheetShown(this);
    }

    @Override
    protected void onStop() {
        mHandler.removeCallbacksAndMessages(null);
        mStatusTab.setShown(false);
        mVideo.stop();
        // ⚠️ D'abord quitter le registre des fenêtres ouvertes : le toast des 3 jours, qui suit,
        // doit prendre la place que lui donne l'écran qui RESTE.
        BrowtherReferralPresenter.sheetHidden(this);
        report();
        // ⚠️ APRÈS `report` : un partage abouti est écrit d'abord — refermer après avoir partagé
        // n'est pas une fermeture (`ReferralSharePrompt.markDismissed`).
        settlePrompt();
        super.onStop();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        mFocused = hasFocus;
        if (!hasFocus) {
            if (mBusy) mLeft = true;
        } else if (mBusy && mLeft) {
            // De retour d'un envoi : la feuille se rend (et le second statut peut s'annoncer).
            endSend();
            return;
        }
        refresh();
    }

    /**
     * ⭐ UNE fois, à la fermeture, si au moins un envoi a abouti : l'écran d'où l'on vient passe à
     * son état « partagé », puis les 3 jours du moment « partage » ({@code shareDone} : il ferme le
     * circuit, retient le partage, et dit les jours offerts un peu après, dans un toast). ⛔ Muet
     * depuis un aperçu de recette.
     */
    private void report() {
        if (!mAchieved || mReported) return;
        mReported = true;
        if (mOnAchieved != null) mOnAchieved.run();
        BrowtherReferralController.get().shareDone(mOrigin, mPreview);
    }

    /**
     * Le partage proposé se referme : la sortie prise (un bouton, sinon la fermeture classique) va
     * au contrôleur, UNE fois. ⚠️ Une fermeture classique APRÈS un partage n'est pas une
     * fermeture : rien ne s'écrit.
     */
    private boolean mPromptSettled;

    private void settlePrompt() {
        Prompt prompt = mPrompt;
        if (prompt == null || mPromptSettled) return;
        mPromptSettled = true;
        PromptExit exit = mPromptExit;
        if (exit == null) {
            if (mAchieved) return;
            exit = PromptExit.DISMISS;
        }
        BrowtherReferralController.get().settleSharePrompt(exit, prompt.profile, mPreview);
    }

    // -------------------- Le dessin --------------------

    private String s(String key) {
        return ReferralStrings.get(getContext(), key);
    }

    private View build() {
        Context context = getContext();
        ReferralUi.Palette p = mP;
        FrameLayout root = new FrameLayout(context);
        GradientDrawable background = new GradientDrawable();
        float radius = ReferralUi.dp(context, 20);
        background.setCornerRadii(new float[] {radius, radius, radius, radius, 0, 0, 0, 0});
        background.setColor(p.screen);
        root.setBackground(background);

        LinearLayout stack = ReferralUi.column(context);
        // ⚠️ En grand d'emblée, et à hauteur FIXE : les deux vignettes et le bouton tiennent sans
        // défiler, et la feuille ne saute pas quand on change d'onglet ou que la vidéo arrive.
        stack.setMinimumHeight(
                Math.round(context.getResources().getDisplayMetrics().heightPixels * 0.86f));

        if (mPrompt == null) {
            TextView title =
                    ReferralUi.text(context, s("invite.share"), 17, ReferralUi.SEMIBOLD, p.text);
            title.setGravity(Gravity.CENTER);
            title.setSingleLine(true);
            title.setEllipsize(TextUtils.TruncateAt.END);
            int titleSide = ReferralUi.dp(context, 56);
            title.setPadding(titleSide, 0, titleSide, 0);
            stack.addView(
                    title,
                    ReferralUi.linear(
                            ReferralUi.MATCH,
                            ReferralUi.dp(context, 44),
                            ReferralUi.dp(context, 10)));
        } else {
            stack.addView(
                    promptHeader(mPrompt), ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        }

        int side = ReferralUi.dp(context, SIDE_DP);
        LinearLayout.LayoutParams tabsParams =
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 4));
        tabsParams.leftMargin = side;
        tabsParams.rightMargin = side;
        tabsParams.bottomMargin = ReferralUi.dp(context, 14);
        stack.addView(mTabs, tabsParams);

        // Ce qui se regarde défile ; ce qui se touche est ÉPINGLÉ en bas (voir `ReferralSheetDialog` :
        // sur un petit écran, un bouton sous le pli ne se voit pas). 🔴 § 12.38 : un fond explicite
        // sur chaque conteneur.
        ScrollView scroll = new ScrollView(context);
        scroll.setBackgroundColor(p.screen);
        FrameLayout holder = new FrameLayout(context);
        holder.setBackgroundColor(p.screen);
        holder.setPadding(side, 0, side, ReferralUi.dp(context, 16));
        mContent.setBackgroundColor(p.screen);
        holder.addView(
                mContent,
                new FrameLayout.LayoutParams(
                        contentWidth(), ReferralUi.WRAP, Gravity.CENTER_HORIZONTAL));
        scroll.addView(holder, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));
        stack.addView(scroll, new LinearLayout.LayoutParams(ReferralUi.MATCH, 0, 1));

        View rule = new View(context);
        rule.setBackgroundColor(p.line);
        stack.addView(rule, ReferralUi.linear(ReferralUi.MATCH, 1));
        FrameLayout footHolder = new FrameLayout(context);
        footHolder.setBackgroundColor(p.screen);
        footHolder.setPadding(side, ReferralUi.dp(context, 12), side, ReferralUi.dp(context, 16));
        mFooter.setBackgroundColor(p.screen);
        footHolder.addView(
                mFooter,
                new FrameLayout.LayoutParams(
                        contentWidth(), ReferralUi.WRAP, Gravity.CENTER_HORIZONTAL));
        stack.addView(footHolder, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        if (mPrompt != null) {
            stack.addView(
                    promptExits(mPrompt), ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        }
        root.addView(stack, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));

        // Fermeture classique, comme les autres feuilles : la croix, le glissé, le retour système.
        ImageView close = ReferralUi.glyph(context, R.drawable.browther_intro_glyph_xmark, 15, p.text2);
        int size = ReferralUi.dp(context, 44);
        int pad = (size - ReferralUi.dp(context, 15)) / 2;
        close.setPadding(pad, pad, pad, pad);
        close.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        close.setContentDescription(s("common.close"));
        close.setOnClickListener(v -> dismiss());
        FrameLayout.LayoutParams closeParams = ReferralUi.frame(size, size, Gravity.TOP | Gravity.END);
        closeParams.topMargin = ReferralUi.dp(context, 10);
        closeParams.setMarginEnd(ReferralUi.dp(context, 6));
        root.addView(close, closeParams);
        return root;
    }

    /**
     * Le titre du partage proposé, au-dessus des onglets (maquette du 2026-10-12) : le compteur
     * (« Browther a retiré 12 heures de musique et flouté 1240 personnes pour toi. ») ou, quand on
     * a vraiment très peu, « Browther t'est utile ? » ; puis la phrase du gain, ⛔ jamais pour qui
     * a payé (la sienne : « il lui servira peut-être autant qu'à toi »).
     */
    private View promptHeader(Prompt prompt) {
        Context context = getContext();
        LinearLayout header = ReferralUi.column(context);
        header.setBackgroundColor(mP.screen);
        int side = ReferralUi.dp(context, SIDE_DP);
        // La croix est en haut à droite : le titre lui laisse sa place.
        header.setPadding(side, ReferralUi.dp(context, 18), ReferralUi.dp(context, 56), 0);
        TextView title =
                ReferralUi.text(context, headline(context, prompt), 19, ReferralUi.SEMIBOLD, mP.text);
        header.addView(title, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        String lead =
                prompt.profile == ReferralSharePrompt.Profile.OFFERED
                        ? s("sharePrompt.leadGain")
                        : s("sharePrompt.leadPaid");
        TextView body = ReferralUi.text(context, lead, 15, ReferralUi.REGULAR, mP.text2);
        header.addView(
                body,
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 6)));
        View space = new View(context);
        header.addView(space, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 10)));
        return header;
    }

    /** La phrase du compteur, dont le CHOIX est dans la règle ({@code ReferralSharePrompt.headline}). */
    private String headline(Context context, Prompt prompt) {
        ReferralSharePrompt.Headline h = prompt.headline;
        String hours = ReferralStrings.plural(context, "sharePrompt.hours", h.hours);
        String persons = ReferralStrings.plural(context, "sharePrompt.persons", h.persons);
        switch (h.kind) {
            case BOTH:
                return ReferralStrings.fill(
                        s("sharePrompt.count.both"), "hours", hours, "persons", persons);
            case MUSIC:
                return ReferralStrings.fill(s("sharePrompt.count.music"), "hours", hours);
            case BLUR:
                return ReferralStrings.fill(s("sharePrompt.count.blur"), "persons", persons);
            case NONE:
            default:
                return s("sharePrompt.title");
        }
    }

    /**
     * Les sorties du partage proposé, sous le pied de l'onglet : « Plus tard » pour tous, « Ne plus
     * me redemander » en plus pour l'abonné et l'accès à vie. La fermeture classique reste (croix,
     * glissé, retour) : il n'attend pas une action (§ 2.2).
     */
    private View promptExits(Prompt prompt) {
        Context context = getContext();
        LinearLayout exits = ReferralUi.row(context);
        exits.setGravity(Gravity.CENTER);
        exits.setBackgroundColor(mP.screen);
        exits.setPadding(0, 0, 0, ReferralUi.dp(context, 8));
        exits.addView(
                ReferralUi.textExit(
                        context,
                        mP,
                        s("sharePrompt.later"),
                        false,
                        false,
                        () -> leave(PromptExit.LATER)));
        if (prompt.profile.canMute()) {
            View space = new View(context);
            exits.addView(space, new LinearLayout.LayoutParams(ReferralUi.dp(context, 12), 1));
            exits.addView(
                    ReferralUi.textExit(
                            context,
                            mP,
                            s("sharePrompt.mute"),
                            false,
                            false,
                            () -> leave(PromptExit.MUTE)));
        }
        return exits;
    }

    private void leave(PromptExit exit) {
        if (mPromptExit == null) mPromptExit = exit;
        dismiss();
    }

    /** Pose l'onglet choisi : ses onglets, ce qui défile, son pied. */
    private void mount() {
        buildTabs();
        mContent.removeAllViews();
        mFooter.removeAllViews();
        boolean status = mTab == Tab.STATUS;
        mStatusTab.setShown(status);
        mContent.addView(
                status ? mStatusTab.content() : mMessageTab.content(),
                new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));
        mFooter.addView(
                status ? mStatusTab.footer() : mMessageTab.footer(),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        refresh();
    }

    private void choose(Tab next) {
        if (next == mTab) return;
        ReferralUi.tick(mTabs);
        mTab = next;
        mount();
    }

    /** Le contrôle segmenté : ⭐ le statut d'abord, le message ensuite. */
    private void buildTabs() {
        Context context = getContext();
        mTabs.removeAllViews();
        int pad = ReferralUi.dp(context, 4);
        mTabs.setPadding(pad, pad, pad, pad);
        mTabs.setBackground(ReferralUi.rounded(mP.track, ReferralUi.dp(context, 12)));
        addTab(Tab.STATUS, "status.tab");
        addTab(Tab.MESSAGE, "share.tabMessage");
    }

    private void addTab(Tab tab, String key) {
        Context context = getContext();
        boolean on = tab == mTab;
        String label = s(key);
        TextView item =
                ReferralUi.text(
                        context,
                        label,
                        14,
                        on ? ReferralUi.SEMIBOLD : ReferralUi.MEDIUM,
                        on ? mP.text : mP.text2);
        item.setGravity(Gravity.CENTER);
        item.setSingleLine(true);
        item.setEllipsize(TextUtils.TruncateAt.END);
        item.setMinimumHeight(ReferralUi.dp(context, 36));
        int padH = ReferralUi.dp(context, 8);
        item.setPadding(padH, 0, padH, 0);
        if (on) {
            item.setBackground(ReferralUi.rounded(mP.panel, ReferralUi.dp(context, 9)));
            item.setElevation(ReferralUi.dp(context, 1.5f));
        }
        item.setClickable(true);
        item.setFocusable(true);
        item.setSelected(on);
        item.setOnClickListener(v -> choose(tab));
        mTabs.addView(item, new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1));
    }
}
