/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.graphics.Bitmap;
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
import org.chromium.chrome.browser.browther_referral.ReferralShareWidgets.VideoTag;
import org.chromium.chrome.browser.browther_referral.core.ReferralShare;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideo.Segment;

import java.io.File;

/**
 * L'onglet <b>« Message »</b> de la feuille « Partager mon code » — port de {@code
 * ReferralMessageShareContent} ({@code ReferralShareSheet.swift}), private/docs/PARRAINAGE.md § 11.
 *
 * <p>⭐ <b>L'aperçu dit ce que fait le geste</b> : le message dans une bulle de discussion, tel que
 * le proche le recevra.
 *
 * <p>⭐ <b>Deux messages, selon la case « Joindre la vidéo »</b> (Karim, 2026-10-08 — un texte et un
 * lien seuls engagent peu) :
 *
 * <ul>
 *   <li>cochée : la VIDÉO, et dessous le texte de l'image du statut, le code en clair, le lien
 *       ({@code ReferralShare.videoMessage}) ;
 *   <li>décochée : l'IMAGE du statut (elle porte déjà le texte et la carte), et dessous le code et
 *       le lien ({@code ReferralShare.imageMessage}).
 * </ul>
 *
 * <p>Un seul fichier par envoi : le texte devient bien sa légende. ⛔ Toujours le sélecteur du
 * système, jamais WhatsApp d'office : on écrit à qui l'on veut, par où l'on veut.
 *
 * <p>🔴 <b>Jamais d'impasse</b> : pas de vidéo ⇒ l'image, sans case à cocher ; aucun fichier ne peut
 * partir (image non écrite, FileProvider qui refuse) ⇒ le message texte d'avant part seul.
 *
 * <p>🔴 Partager ne crée AUCUNE invitation (§ 12.1) : un partage abouti n'ouvre droit qu'aux 3
 * jours.
 */
final class ReferralShareMessageTab {
    /** La bulle : les couleurs d'une discussion, pas celles de l'app. */
    private static final class Chat {
        final int wall;
        final int bubble;
        final int ink;
        final int link;

        Chat(int wall, int bubble, int ink, int link) {
            this.wall = wall;
            this.bubble = bubble;
            this.ink = ink;
            this.link = link;
        }

        static final Chat LIGHT = new Chat(0xFFEFEAE2, 0xFFD9FDD3, 0xFF111B21, 0xFF027EB5);
        static final Chat DARK = new Chat(0xFF0B141A, 0xFF144D37, 0xFFE9EDEF, 0xFF7DD3FC);
    }

    /** La bulle de la vidéo : large, la vidéo y est recadrée et le texte coupé. */
    private static final float VIDEO_BUBBLE_DP = 236;

    private static final float VIDEO_THUMB_DP = 150;

    /**
     * Dans l'aperçu, le texte de la vidéo ne prend pas toute la feuille : le message, lui, part en
     * entier.
     */
    private static final int VIDEO_TEXT_LINES = 5;

    /** La bulle de l'image : l'image entière, à ses proportions (9:16). */
    private static final float IMAGE_DP = 150;

    private final ReferralShareSheet mSheet;
    private final Context mContext;
    private final ReferralUi.Palette mP;
    private final Chat mChat;

    private boolean mAttach = true;
    private int mVideoSeconds = -1;

    private @Nullable FrameLayout mWall;
    private @Nullable View mAttachRow;
    private @Nullable CheckMark mAttachCheck;
    private @Nullable GaugeButton mButton;

    ReferralShareMessageTab(ReferralShareSheet sheet, ReferralUi.Palette palette) {
        mSheet = sheet;
        mContext = sheet.getContext();
        mP = palette;
        mChat = palette.dark ? Chat.DARK : Chat.LIGHT;
    }

    private String s(String key) {
        return ReferralStrings.get(mContext, key);
    }

    private boolean withVideo() {
        return mSheet.video().offered() && mAttach;
    }

    /** ⚠️ On n'attend que ce qui part : la vidéo si elle est cochée. */
    private boolean canSend() {
        return !mSheet.busy() && (!withVideo() || mSheet.video().file() != null);
    }

    // -------------------- Ce qui s'affiche --------------------

    /** La discussion et sa bulle — ce qui défile. */
    View content() {
        FrameLayout wall = new FrameLayout(mContext);
        wall.setBackground(ReferralUi.rounded(mChat.wall, ReferralUi.dp(mContext, 20)));
        int padH = ReferralUi.dp(mContext, 12);
        int padV = ReferralUi.dp(mContext, 16);
        wall.setPadding(padH, padV, padH, padV);
        // La bulle envoyée reste du même côté, même en arabe (le texte, lui, suit sa langue) : le
        // mur est TOUJOURS de gauche à droite, « la fin » y est donc la droite.
        wall.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        wall.setContentDescription(s("share.previewA11y"));
        wall.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        mWall = wall;
        fillWall();
        return wall;
    }

    private void fillWall() {
        FrameLayout wall = mWall;
        if (wall == null) return;
        wall.removeAllViews();
        float widthDp = (withVideo() ? VIDEO_BUBBLE_DP : IMAGE_DP) + 10;
        wall.addView(
                bubble(),
                new FrameLayout.LayoutParams(
                        ReferralUi.dp(mContext, widthDp), ReferralUi.WRAP, Gravity.END));
    }

    private View bubble() {
        boolean rtl = mSheet.texts().isRtl();
        LinearLayout bubble = ReferralUi.column(mContext);
        int pad = ReferralUi.dp(mContext, 5);
        bubble.setPadding(pad, pad, pad, pad);
        bubble.setBackground(ReferralUi.rounded(mChat.bubble, ReferralUi.dp(mContext, 12)));
        bubble.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        int gap = ReferralUi.dp(mContext, 6);

        FrameLayout thumb = new FrameLayout(mContext);
        thumb.setBackgroundColor(0xFF000000);
        ReferralShareWidgets.clipRounded(thumb, ReferralUi.dp(mContext, 9));
        if (withVideo()) {
            File file = mSheet.video().file();
            if (file != null) {
                VideoTag tag = new VideoTag(mContext);
                tag.setSeconds(mVideoSeconds);
                thumb.addView(
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
                                ReferralUi.WRAP, ReferralUi.WRAP, Gravity.BOTTOM | Gravity.START);
                tagParams.setMarginStart(ReferralUi.dp(mContext, 8));
                tagParams.bottomMargin = ReferralUi.dp(mContext, 7);
                thumb.addView(tag, tagParams);
            } else {
                addSpinner(thumb);
            }
            bubble.addView(
                    thumb, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(mContext, VIDEO_THUMB_DP)));

            // Le texte de l'image du statut, en clair — coupé ici, entier dans le message.
            StringBuilder body = new StringBuilder();
            for (String paragraph : mSheet.texts().paragraphs) {
                if (body.length() > 0) body.append("\n\n");
                body.append(ReferralShare.stripStatusMarks(paragraph));
            }
            TextView text = line(body.toString(), mChat.ink, rtl);
            text.setMaxLines(VIDEO_TEXT_LINES);
            text.setEllipsize(TextUtils.TruncateAt.END);
            bubble.addView(text, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, gap));
        } else {
            Bitmap image = mSheet.image();
            if (image != null) {
                ImageView view = new ImageView(mContext);
                view.setScaleType(ImageView.ScaleType.CENTER_CROP);
                view.setImageBitmap(image);
                thumb.addView(view, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
            } else {
                addSpinner(thumb);
            }
            bubble.addView(
                    thumb,
                    ReferralUi.linear(
                            ReferralUi.MATCH, Math.round(ReferralUi.dp(mContext, IMAGE_DP) * 16f / 9f)));
        }

        bubble.addView(
                line(mSheet.texts().codeLine(mSheet.code()), mChat.ink, rtl),
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, gap));
        // ⚠️ Un lien se lit de gauche à droite, même en arabe.
        TextView link = line(ReferralShareWidgets.bareLink(mSheet.link()), mChat.link, false);
        link.setSingleLine(true);
        link.setEllipsize(TextUtils.TruncateAt.END);
        link.setPadding(
                link.getPaddingLeft(), 0, link.getPaddingRight(), ReferralUi.dp(mContext, 2));
        bubble.addView(
                link, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(mContext, 1)));
        return bubble;
    }

    /** Une ligne de la bulle, alignée sur le début de SA langue. */
    private TextView line(String value, int color, boolean rtl) {
        TextView view = ReferralUi.text(mContext, value, 13, ReferralUi.REGULAR, color);
        int side = ReferralUi.dp(mContext, 4);
        view.setPadding(side, 0, side, 0);
        view.setLayoutDirection(rtl ? View.LAYOUT_DIRECTION_RTL : View.LAYOUT_DIRECTION_LTR);
        view.setTextDirection(rtl ? View.TEXT_DIRECTION_RTL : View.TEXT_DIRECTION_LTR);
        view.setTextAlignment(View.TEXT_ALIGNMENT_VIEW_START);
        return view;
    }

    private void addSpinner(FrameLayout thumb) {
        int size = ReferralUi.dp(mContext, 28);
        thumb.addView(
                ReferralShareWidgets.spinner(mContext, 0xFFFFFFFF),
                new FrameLayout.LayoutParams(size, size, Gravity.CENTER));
    }

    /** « Joindre la vidéo » (si elle est proposée) et le bouton — épinglés au pied de la feuille. */
    View footer() {
        LinearLayout column = ReferralUi.column(mContext);
        mAttachRow = null;
        mAttachCheck = null;
        if (mSheet.video().offered()) {
            LinearLayout row = ReferralUi.row(mContext);
            row.setMinimumHeight(ReferralUi.dp(mContext, 44));
            int side = ReferralUi.dp(mContext, 2);
            row.setPadding(side, 0, side, 0);
            // Une case : pleine (l'encre du thème) quand la vidéo est jointe.
            CheckMark check = new CheckMark(mContext, 22, 7, mP.text, 0, mP.text, mP.screen);
            row.addView(check);
            String label = s("share.attachVideo");
            TextView labelView = ReferralUi.text(mContext, label, 15, ReferralUi.REGULAR, mP.text);
            labelView.setTextAlignment(View.TEXT_ALIGNMENT_VIEW_START);
            LinearLayout.LayoutParams labelParams = new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1);
            labelParams.setMarginStart(ReferralUi.dp(mContext, 12));
            row.addView(labelView, labelParams);
            row.setClickable(true);
            row.setFocusable(true);
            row.setContentDescription(label);
            row.setOnClickListener(
                    v -> {
                        if (mSheet.busy()) return;
                        ReferralUi.tick(v);
                        mAttach = !mAttach;
                        // Une autre bulle : la vidéo et son texte, ou l'image.
                        fillWall();
                        mSheet.refresh();
                    });
            LinearLayout.LayoutParams rowParams = ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP);
            rowParams.bottomMargin = ReferralUi.dp(mContext, 8);
            column.addView(row, rowParams);
            mAttachRow = row;
            mAttachCheck = check;
        }
        GaugeButton button =
                new GaugeButton(mContext, mP, R.drawable.browther_referral_glyph_share, this::send);
        button.setLabel(s("share.send"));
        mButton = button;
        column.addView(button);
        return column;
    }

    /** Met à jour ce qui change sans rien reconstruire : la case, le bouton. */
    void sync() {
        if (mAttachCheck != null) mAttachCheck.setChecked(mAttach);
        if (mAttachRow != null) {
            mAttachRow.setSelected(mAttach);
            mAttachRow.setEnabled(!mSheet.busy());
        }
        GaugeButton button = mButton;
        if (button == null) return;
        button.setBusy(mSheet.busy());
        button.setAvailable(canSend());
    }

    // -------------------- Le geste --------------------

    /**
     * Ce qui part : la vidéo cochée et arrivée, sinon l'image, sinon le message texte d'avant. ⚠️
     * {@code media} dit ce qui est RÉELLEMENT joint ({@code referral_shared {format: message,
     * media}}), ⛔ absent si le texte part seul. Seule une cible CHOISIE dans le sélecteur compte.
     */
    private void send() {
        if (mSheet.busy()) return;
        ReferralStatus status = mSheet.status();
        String code = mSheet.code();
        String codeLine = mSheet.texts().codeLine(code);
        String url = status.referral.url;
        File video = withVideo() ? mSheet.video().file() : null;
        File image = mSheet.imageFile();

        ReferralSharing.Launch launch = ReferralSharing.Launch.NONE;
        if (video != null) {
            launch =
                    ReferralSharing.shareMessageFile(
                            mSheet.activity(),
                            video,
                            ReferralShare.videoMessage(mSheet.texts().paragraphs, codeLine, code, url),
                            () -> sent(Segment.VIDEO));
        } else if (image != null) {
            launch =
                    ReferralSharing.shareMessageFile(
                            mSheet.activity(),
                            image,
                            ReferralShare.imageMessage(codeLine, code, url),
                            () -> sent(Segment.IMAGE));
        }
        // 🔴 Jamais d'impasse : aucun fichier n'a pu partir ⇒ le message texte d'avant, seul.
        if (launch == ReferralSharing.Launch.NONE) {
            launch = ReferralSharing.shareText(mSheet.activity(), status, () -> sent(null));
        }
        if (launch != ReferralSharing.Launch.NONE) mSheet.beginSend();
    }

    private void sent(@Nullable Segment media) {
        // Un sélecteur resté ouvert derrière une feuille refermée : plus personne pour compter.
        if (!mSheet.isShowing()) return;
        ReferralSharing.noteMessage(
                mSheet.origin(), mSheet.preview(), ReferralSharing.Result.SHARED, media);
        mSheet.onSent();
        mSheet.onFinished();
    }
}
