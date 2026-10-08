/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.ReferralShareWidgets.CheckMark;
import org.chromium.chrome.browser.browther_referral.ReferralShareWidgets.GaugeButton;
import org.chromium.chrome.browser.browther_referral.ReferralShareWidgets.StatusFrame;
import org.chromium.chrome.browser.browther_referral.ReferralShareWidgets.VideoTag;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideo;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideo.Cta;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideo.Flags;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideo.Segment;

import java.io.File;
import java.util.List;

/**
 * L'onglet <b>« Statut WhatsApp »</b> de la feuille « Partager mon code » — port de {@code
 * ReferralStatusShareContent} ({@code ReferralShareSheet.swift}), private/docs/PARRAINAGE.md § 11.
 *
 * <p>⭐ <b>L'aperçu dit ce que fait le geste</b> (Karim, 2026-09-29) : chaque statut est montré dans
 * un cadre de statut — la barre en haut, le LIEN EN LÉGENDE en bas, là où WhatsApp le posera.
 *
 * <p>⭐ <b>Deux statuts, côte à côte, à cocher</b> (choix A de Karim sur maquette, 2026-10-08) : la
 * vidéo de présentation et l'image qui porte le code. UN bouton, qui publie le prochain statut
 * coché ; après le premier, il annonce le second (« 2 sur 2 ») et <b>se déclenche tout seul</b> au
 * bout d'un court décompte, montré par la jauge du bouton — un tap le devance.
 *
 * <p>⛔ Ce passage automatique : jamais sans la jauge, jamais app en arrière-plan, et UNE fois par
 * envoi réussi. ⚠️ Sur Android on revient de WhatsApp À LA MAIN : le décompte ne démarre qu'au
 * retour, quand la fenêtre de la feuille retrouve le focus ({@link ReferralShareSheet#focused}) —
 * et il repart de zéro si elle le reperd.
 *
 * <p>🔴 <b>Un envoi par statut</b> : WhatsApp ne donne le lien qu'au premier média d'un envoi
 * ({@code core/ReferralStatusVideo}). ⛔ Ne pas regrouper les deux.
 *
 * <p>🔴 Sans vidéo (réseau, vidéo coupée, absente dans la langue, pas arrivée à temps) : UN grand
 * cadre, l'image seule, le bouton « Publier en statut WhatsApp » — le geste d'avant. ⛔ Aucun bouton
 * ne dépend de la vidéo.
 *
 * <p>⚠️ Les vignettes défilent, le bouton et sa ligne sont ÉPINGLÉS au pied de la feuille : sur un
 * petit écran un bouton sous le pli ne se voit pas (recette du 2026-09-27 sur un Huawei P20).
 */
final class ReferralShareStatusTab {
    private final ReferralShareSheet mSheet;
    private final Context mContext;
    private final ReferralUi.Palette mP;
    private final Handler mHandler = new Handler(Looper.getMainLooper());

    private Flags mPicked = Flags.BOTH;
    private Flags mSent = Flags.NONE;
    /**
     * Le passage automatique au statut suivant : armé par un envoi réussi, désarmé dès qu'un envoi
     * démarre (le sien compris).
     */
    private boolean mAutoArmed;
    /** Le décompte tourne (la jauge du bouton avance). */
    private boolean mCounting;
    /** L'onglet est celui qu'on voit. */
    private boolean mShown;
    private int mVideoSeconds = -1;

    private @Nullable Card mVideoCard;
    private @Nullable Card mImageCard;
    private @Nullable GaugeButton mButton;
    private @Nullable TextView mHint;

    /** Une vignette : son cadre, sa coche, ses deux lignes. */
    private static final class Card {
        final LinearLayout view;
        final StatusFrame frame;
        final CheckMark check;
        final String label;

        Card(LinearLayout view, StatusFrame frame, CheckMark check, String label) {
            this.view = view;
            this.frame = frame;
            this.check = check;
            this.label = label;
        }
    }

    ReferralShareStatusTab(ReferralShareSheet sheet, ReferralUi.Palette palette) {
        mSheet = sheet;
        mContext = sheet.getContext();
        mP = palette;
    }

    private String s(String key) {
        return ReferralStrings.get(mContext, key);
    }

    // -------------------- Où l'on en est --------------------

    /** Deux statuts à cocher — tant qu'on attend encore la vidéo, on la propose. */
    private boolean two() {
        return mSheet.video().offered();
    }

    /** Sans vidéo, une seule chose à publier : l'image, d'office. */
    private Flags wanted() {
        return two() ? mPicked : Flags.IMAGE_ONLY;
    }

    private @Nullable Segment next() {
        List<Segment> queue = ReferralStatusVideo.queue(wanted(), mSent);
        return queue.isEmpty() ? null : queue.get(0);
    }

    private Cta cta() {
        return ReferralStatusVideo.cta(wanted(), mSent);
    }

    private @Nullable File file(Segment segment) {
        return segment == Segment.VIDEO ? mSheet.video().file() : mSheet.imageFile();
    }

    private boolean canPublish() {
        Segment next = next();
        return !mSheet.busy() && next != null && file(next) != null;
    }

    private boolean autoOn() {
        return mShown
                && two()
                && mAutoArmed
                && mSheet.focused()
                && canPublish()
                && cta().kind == Cta.Kind.NEXT;
    }

    // -------------------- Ce qui s'affiche --------------------

    /** Les vignettes (ou le grand cadre de l'image seule) — ce qui défile. */
    View content() {
        mVideoCard = null;
        mImageCard = null;
        if (!two()) return single();
        LinearLayout row = new LinearLayout(mContext);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.TOP);
        // ⭐ L'ordre des vignettes EST celui des envois : une seule source.
        boolean first = true;
        for (Segment segment : ReferralStatusVideo.segments(true)) {
            Card card = card(segment);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1);
            if (!first) params.setMarginStart(ReferralUi.dp(mContext, 12));
            first = false;
            row.addView(card.view, params);
            if (segment == Segment.VIDEO) {
                mVideoCard = card;
            } else {
                mImageCard = card;
            }
        }
        // Deux vignettes de 190 dp au plus, centrées.
        FrameLayout holder = new FrameLayout(mContext);
        holder.addView(
                row,
                new FrameLayout.LayoutParams(
                        Math.min(mSheet.contentWidth(), ReferralUi.dp(mContext, 2 * 190 + 12)),
                        ReferralUi.WRAP,
                        Gravity.CENTER_HORIZONTAL));
        return holder;
    }

    private View single() {
        StatusFrame frame = new StatusFrame(mContext, false, mSheet.link());
        frame.setMedia(image());
        frame.setLoading(mSheet.image() == null);
        frame.setContentDescription(s("status.previewA11y"));
        frame.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        FrameLayout holder = new FrameLayout(mContext);
        holder.addView(
                frame,
                new FrameLayout.LayoutParams(
                        Math.min(mSheet.contentWidth(), ReferralUi.dp(mContext, 232)),
                        ReferralUi.WRAP,
                        Gravity.CENTER_HORIZONTAL));
        return holder;
    }

    private Card card(Segment segment) {
        boolean video = segment == Segment.VIDEO;
        String title = s(video ? "status.videoLabel" : "status.imageLabel");
        String sub = s(video ? "status.videoSub" : "status.imageSub");
        LinearLayout view = ReferralUi.column(mContext);

        FrameLayout top = new FrameLayout(mContext);
        StatusFrame frame = new StatusFrame(mContext, true, mSheet.link());
        frame.setMedia(video ? video() : image());
        top.addView(frame, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));
        // La coche, ronde, en haut du côté de la fin : pleine quand le statut est coché.
        CheckMark check =
                new CheckMark(mContext, 26, 13, mP.onPrimary, 0x40000000, 0xFFFFFFFF, mP.primary);
        int checkSize = ReferralUi.dp(mContext, 26);
        FrameLayout.LayoutParams checkParams =
                new FrameLayout.LayoutParams(checkSize, checkSize, Gravity.TOP | Gravity.END);
        checkParams.topMargin = ReferralUi.dp(mContext, 14);
        checkParams.setMarginEnd(ReferralUi.dp(mContext, 9));
        top.addView(check, checkParams);
        view.addView(top, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));

        TextView titleView = ReferralUi.text(mContext, title, 15, ReferralUi.SEMIBOLD, mP.text);
        titleView.setSingleLine(true);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        titleView.setTextAlignment(View.TEXT_ALIGNMENT_VIEW_START);
        LinearLayout.LayoutParams titleParams =
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(mContext, 8));
        int side = ReferralUi.dp(mContext, 2);
        titleParams.leftMargin = side;
        titleParams.rightMargin = side;
        view.addView(titleView, titleParams);
        TextView subView = ReferralUi.text(mContext, sub, 13, ReferralUi.REGULAR, mP.text2);
        subView.setSingleLine(true);
        subView.setEllipsize(TextUtils.TruncateAt.END);
        subView.setTextAlignment(View.TEXT_ALIGNMENT_VIEW_START);
        LinearLayout.LayoutParams subParams =
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(mContext, 2));
        subParams.leftMargin = side;
        subParams.rightMargin = side;
        view.addView(subView, subParams);

        view.setClickable(true);
        view.setFocusable(true);
        view.setOnClickListener(v -> toggle(v, segment));
        return new Card(view, frame, check, title + ", " + sub);
    }

    /** La vidéo qui joue, muette, en boucle — sa pastille (▶ et la durée) par-dessus. */
    private @Nullable View video() {
        File file = mSheet.video().file();
        if (file == null) return null;
        FrameLayout media = new FrameLayout(mContext);
        VideoTag tag = new VideoTag(mContext);
        tag.setSeconds(mVideoSeconds);
        media.addView(
                new ReferralStatusVideoPreview(
                        mContext,
                        file,
                        seconds -> {
                            mVideoSeconds = seconds;
                            tag.setSeconds(seconds);
                        }),
                new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        FrameLayout.LayoutParams tagParams =
                new FrameLayout.LayoutParams(
                        ReferralUi.WRAP, ReferralUi.WRAP, Gravity.TOP | Gravity.START);
        tagParams.topMargin = ReferralUi.dp(mContext, 18);
        tagParams.setMarginStart(ReferralUi.dp(mContext, 9));
        media.addView(tag, tagParams);
        return media;
    }

    /** L'image qui porte le code — la même que celle qui part. */
    private @Nullable View image() {
        Bitmap bitmap = mSheet.image();
        if (bitmap == null) return null;
        ImageView view = new ImageView(mContext);
        view.setScaleType(ImageView.ScaleType.CENTER_CROP);
        view.setImageBitmap(bitmap);
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        return view;
    }

    /** Le bouton et sa ligne d'aide — épinglés au pied de la feuille. */
    View footer() {
        // Un pied neuf : le décompte, s'il doit tourner, repart avec SON bouton (`sync`).
        stopCounting();
        LinearLayout column = ReferralUi.column(mContext);
        GaugeButton button =
                new GaugeButton(mContext, mP, R.drawable.browther_referral_glyph_status, this::publish);
        mButton = button;
        column.addView(button);
        TextView hint = ReferralUi.footnote(mContext, mP, "");
        mHint = hint;
        column.addView(
                hint, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(mContext, 10)));
        return column;
    }

    /** L'onglet devient (ou cesse d'être) celui qu'on voit. */
    void setShown(boolean shown) {
        mShown = shown;
        if (!shown) stopCounting();
    }

    /** Met à jour ce qui change sans rien reconstruire : coches, « Publié », bouton, décompte. */
    void sync() {
        sync(mVideoCard, Segment.VIDEO, mSheet.video().file() == null);
        sync(mImageCard, Segment.IMAGE, mSheet.image() == null);
        GaugeButton button = mButton;
        if (button == null) return;

        // ⭐ Le statut suivant part tout seul quand la jauge est pleine. Le décompte ne repart de
        // zéro que si SA condition change.
        boolean auto = autoOn();
        if (auto && !mCounting) {
            mCounting = true;
            button.startGauge(ReferralStatusVideo.NEXT_AUTO_MS);
            mHandler.postDelayed(mAutoPublish, ReferralStatusVideo.NEXT_AUTO_MS);
        } else if (!auto && mCounting) {
            stopCounting();
        }

        button.setLabel(buttonText());
        button.setBusy(mSheet.busy());
        button.setAvailable(canPublish());
        TextView hint = mHint;
        if (hint == null) return;
        String text = hint(auto);
        hint.setVisibility(text == null ? View.GONE : View.VISIBLE);
        if (text != null) hint.setText(text);
    }

    private void sync(@Nullable Card card, Segment segment, boolean loading) {
        if (card == null) return;
        boolean picked = mPicked.get(segment);
        boolean sent = mSent.get(segment);
        card.frame.setLoading(loading);
        card.frame.setDimmed(!picked && !sent);
        card.frame.setSent(sent ? s("status.published") : null);
        card.check.setVisibility(sent ? View.GONE : View.VISIBLE);
        card.check.setChecked(picked);
        card.view.setEnabled(!sent);
        card.view.setSelected(picked);
        card.view.setContentDescription(
                sent ? card.label + ", " + s("status.published") : card.label);
    }

    private final Runnable mAutoPublish =
            () -> {
                mCounting = false;
                // La condition a pu tomber entre-temps sans qu'on nous le dise : on la relit.
                if (autoOn()) publish();
            };

    private void stopCounting() {
        mCounting = false;
        mHandler.removeCallbacks(mAutoPublish);
        if (mButton != null) mButton.stopGauge();
    }

    // -------------------- Le bouton et sa ligne --------------------

    private String buttonText() {
        if (!two()) return s("invite.shareStatus");
        Cta cta = cta();
        switch (cta.kind) {
            case BOTH:
                return s("status.publishBoth");
            case ONE:
                return s(cta.segment == Segment.VIDEO ? "status.publishVideo" : "status.publishImage");
            case NEXT:
                return s(
                        cta.segment == Segment.VIDEO
                                ? "status.publishVideoNext"
                                : "status.publishImageNext");
            case NONE:
                return s("status.pickOne");
            case DONE:
            default:
                return s("invite.shareStatus");
        }
    }

    private @Nullable String hint(boolean auto) {
        if (!two()) return null;
        Cta cta = cta();
        switch (cta.kind) {
            case BOTH:
                return s("status.hintBoth");
            case ONE:
                return s("status.hintOne");
            case NEXT:
                // Ce qui RESTE est `cta.segment` : c'est l'autre qui vient de partir.
                if (auto) {
                    return s(
                            cta.segment == Segment.VIDEO
                                    ? "status.hintImageDoneAuto"
                                    : "status.hintVideoDoneAuto");
                }
                return s(
                        cta.segment == Segment.VIDEO
                                ? "status.hintImageDone"
                                : "status.hintVideoDone");
            case NONE:
                return s("status.hintNone");
            case DONE:
            default:
                return null;
        }
    }

    // -------------------- Les gestes --------------------

    private void toggle(View card, Segment segment) {
        if (mSheet.busy() || mSent.get(segment)) return;
        ReferralUi.tick(card);
        mPicked = mPicked.with(segment, !mPicked.get(segment));
        mSheet.refresh();
    }

    /**
     * UN envoi : le prochain statut coché, avec le lien SEUL en texte (WhatsApp en fait la
     * légende). Ouvert directement dans WhatsApp : ouvrir vaut « partagé », Android n'en dira rien
     * de plus ; par le sélecteur du système (WhatsApp absent), seule une cible CHOISIE compte. ⚠️
     * Chaque envoi s'écrit ({@code referral_shared {format: status, media}}) — muet pendant un
     * aperçu de recette (§ 13.8).
     */
    private void publish() {
        if (mSheet.busy()) return;
        Segment segment = next();
        if (segment == null) return;
        mAutoArmed = false;
        stopCounting();
        File file = file(segment);
        ReferralSharing.Launch launch =
                file == null
                        ? ReferralSharing.Launch.NONE
                        : ReferralSharing.shareStatusFile(
                                mSheet.activity(), file, mSheet.link(), () -> sent(segment));
        switch (launch) {
            case DIRECT:
                mSheet.beginSend();
                sent(segment);
                break;
            case CHOOSER:
                mSheet.beginSend();
                break;
            case NONE:
            default:
                failed(segment);
                break;
        }
    }

    private void sent(Segment segment) {
        // Un sélecteur resté ouvert derrière une feuille refermée : plus personne pour compter.
        if (!mSheet.isShowing() || mSent.get(segment)) return;
        ReferralSharing.noteStatus(
                mSheet.origin(), mSheet.preview(), ReferralSharing.Result.SHARED, segment);
        Flags wanted = wanted();
        mSent = mSent.with(segment, true);
        mSheet.onSent();
        // Le dernier statut coché est parti : la feuille se referme. Sinon elle reste, le bouton
        // annonce le suivant, et sa jauge démarre au retour dans Browther.
        if (ReferralStatusVideo.queue(wanted, mSent).isEmpty()) {
            mSheet.onFinished();
            return;
        }
        mAutoArmed = true;
        mSheet.refresh();
    }

    /** Rien n'a pu partir : on le dit (en haut — le bouton est en bas), et rien n'est coché « parti ». */
    private void failed(Segment segment) {
        ReferralSharing.noteStatus(
                mSheet.origin(), mSheet.preview(), ReferralSharing.Result.UNAVAILABLE, segment);
        ReferralToast.show(
                mSheet.activity(),
                s(segment == Segment.VIDEO ? "status.failedVideo" : "status.failed"),
                null,
                null,
                null,
                ReferralShareSheet.FAILURE_TOAST_MS);
        mSheet.refresh();
    }
}
