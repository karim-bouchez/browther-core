/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.WRAP;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dpf;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Shader;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.LayerDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.chromium.chrome.R;

/**
 * 5 · Navigateur par défaut. L'écran montre le <b>bénéfice</b> — un lien reçu dans une conversation
 * qui s'ouvre protégé — plutôt que le chemin dans les réglages : c'est ce qui décide, et le chemin,
 * Android le montre lui-même juste après (feuille système du rôle « navigateur »).
 *
 * <p>Saute si Browther est déjà le navigateur par défaut.
 */
final class BrowtherIntroDefaultStep extends BrowtherIntroStepView {
    private final View mSheet;
    private boolean mSheetShown;

    BrowtherIntroDefaultStep(Context context, BrowtherIntroModel model) {
        super(context, model);
        Slots slots =
                template(
                        null,
                        context.getString(R.string.browther_intro_default_title),
                        context.getString(R.string.browther_intro_default_subtitle),
                        null);

        FrameLayout scene = new FrameLayout(context);
        scene.setBackground(BrowtherIntroUi.rounded(BrowtherIntroUi.CANVAS, dpf(context, 18)));
        scene.setClipToOutline(true);
        slots.mScene.addView(scene, BrowtherIntroUi.frame(MATCH, MATCH, Gravity.TOP));

        scene.addView(conversation(context), BrowtherIntroUi.frame(MATCH, MATCH, Gravity.TOP));
        mSheet = browserSheet(context);
        scene.addView(mSheet, BrowtherIntroUi.frame(MATCH, dp(context, 240), Gravity.BOTTOM));
        mSheet.setTranslationY(dp(context, 340));

        BrowtherIntroWidgets.Button primary =
                new BrowtherIntroWidgets.Button(
                        context,
                        R.string.set_default_browser,
                        BrowtherIntroWidgets.Button.Style.PRIMARY);
        primary.setOnClickListener(v -> mModel.setAsDefaultBrowser());
        slots.mActions.addView(primary);
        BrowtherIntroWidgets.Button later =
                new BrowtherIntroWidgets.Button(
                        context,
                        R.string.browther_intro_later_button,
                        BrowtherIntroWidgets.Button.Style.GHOST);
        later.setOnClickListener(v -> mModel.later());
        slots.mActions.addView(later);
    }

    @Override
    void bind(boolean animated) {}

    @Override
    void onActivated() {
        if (mSheetShown) return;
        mSheetShown = true;
        // Browther monte par-dessus la conversation : c'est le « ouvert dans Browther » qu'on veut
        // faire comprendre.
        mSheet.animate()
                .translationY(0)
                .setStartDelay(600)
                .setDuration(650)
                .setInterpolator(BrowtherIntroUi.EASE_OUT)
                .start();
    }

    /**
     * Une conversation, reconnaissable comme telle : barre de contact, fond propre à la messagerie,
     * bulles asymétriques. Le fond est celui de WhatsApp (choix de Karim, 2026-09-12 : la scène
     * n'agit pas sur le service, elle illustre un lien reçu).
     */
    private static View conversation(Context context) {
        LinearLayout column = BrowtherIntroUi.column(context);

        LinearLayout bar = BrowtherIntroUi.row(context, 9);
        bar.setPadding(dp(context, 12), 0, dp(context, 12), 0);
        bar.setBackgroundColor(BrowtherIntroUi.SURFACE);
        bar.addView(
                BrowtherIntroUi.glyph(context, R.drawable.browther_intro_glyph_chevron_left, 15,
                        0xFF25D366));
        FrameLayout avatar = new FrameLayout(context);
        avatar.setBackground(BrowtherIntroUi.capsule(0xFFCFD6CB));
        avatar.addView(
                BrowtherIntroUi.glyph(context, R.drawable.browther_intro_glyph_people, 15,
                        0xFF6B7A68),
                BrowtherIntroUi.frame(dp(context, 15), dp(context, 15), Gravity.CENTER));
        bar.addView(avatar, BrowtherIntroUi.linear(dp(context, 30), dp(context, 30)));
        LinearLayout names = BrowtherIntroUi.column(context);
        names.addView(
                BrowtherIntroUi.text(context, R.string.browther_intro_demo_contact_name, 14,
                        BrowtherIntroUi.SEMIBOLD, BrowtherIntroUi.INK));
        names.addView(
                BrowtherIntroUi.text(context, R.string.browther_intro_demo_messaging_app, 11,
                        BrowtherIntroUi.REGULAR, BrowtherIntroUi.INK_SOFT),
                BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(WRAP, WRAP), dp(context, 1)));
        bar.addView(names, new LinearLayout.LayoutParams(0, WRAP, 1f));
        bar.addView(
                BrowtherIntroUi.glyph(context, R.drawable.browther_intro_glyph_video, 15,
                        BrowtherIntroUi.INK_SOFT));
        bar.addView(
                BrowtherIntroUi.glyph(context, R.drawable.browther_intro_glyph_phone, 15,
                        BrowtherIntroUi.INK_SOFT));
        column.addView(bar, BrowtherIntroUi.linear(MATCH, dp(context, 46)));

        LinearLayout messages = BrowtherIntroUi.column(context);
        BrowtherIntroUi.spacing(messages, 6);
        messages.setPadding(dp(context, 12), dp(context, 12), dp(context, 12), dp(context, 12));
        Bitmap wallpaper =
                BrowtherIntroUi.decodeAsset(
                        context, BrowtherIntroUi.ASSETS + "browther-chat-wallpaper-dark.png", 0);
        if (wallpaper != null) {
            // L'image est à l'échelle 1x de l'iOS : un pixel de l'image = un dp.
            wallpaper.setDensity(android.util.DisplayMetrics.DENSITY_DEFAULT);
            BitmapDrawable tile = new BitmapDrawable(context.getResources(), wallpaper);
            tile.setTileModeXY(Shader.TileMode.REPEAT, Shader.TileMode.REPEAT);
            messages.setBackground(tile);
        }
        TextView incoming =
                BrowtherIntroUi.text(context, R.string.browther_intro_demo_message_incoming, 14.5f,
                        BrowtherIntroUi.REGULAR, BrowtherIntroUi.INK);
        incoming.setPadding(dp(context, 12), dp(context, 8), dp(context, 12), dp(context, 8));
        incoming.setBackground(bubble(context, BrowtherIntroUi.BACKGROUND));
        messages.addView(incoming, BrowtherIntroUi.linear(WRAP, WRAP));
        messages.addView(linkBubble(context), BrowtherIntroUi.linear(dp(context, 230), WRAP));
        column.addView(messages, new LinearLayout.LayoutParams(MATCH, 0, 1f));
        return column;
    }

    /** Coins asymétriques d'une bulle reçue : le coin bas-début est pincé. */
    private static GradientDrawable bubble(Context context, int color) {
        float r = dpf(context, 14);
        float pinched = dpf(context, 3);
        boolean rtl =
                TextUtils.getLayoutDirectionFromLocale(
                                context.getResources().getConfiguration().getLocales().get(0))
                        == View.LAYOUT_DIRECTION_RTL;
        return rtl
                ? BrowtherIntroUi.corners(color, r, r, pinched, r)
                : BrowtherIntroUi.corners(color, r, r, r, pinched);
    }

    /** La bulle qui porte le lien : c'est de là que part la feuille du navigateur. */
    private static View linkBubble(Context context) {
        LinearLayout bubble = BrowtherIntroUi.column(context);
        bubble.setBackground(bubble(context, BrowtherIntroUi.BACKGROUND));
        bubble.setClipToOutline(true);
        View image = new View(context);
        image.setBackground(
                new GradientDrawable(
                        GradientDrawable.Orientation.TL_BR, new int[] {0xFFE7C9A0, 0xFFC98F5B}));
        bubble.addView(image, BrowtherIntroUi.linear(MATCH, dp(context, 58)));
        LinearLayout text = BrowtherIntroUi.column(context);
        text.setPadding(dp(context, 10), dp(context, 7), dp(context, 10), dp(context, 7));
        text.addView(
                BrowtherIntroUi.text(context, R.string.browther_intro_demo_article_title, 13.5f,
                        BrowtherIntroUi.SEMIBOLD, BrowtherIntroUi.INK));
        text.addView(
                BrowtherIntroUi.text(context, R.string.browther_intro_demo_site_name, 12,
                        BrowtherIntroUi.REGULAR, BrowtherIntroUi.INK_SOFT),
                BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(WRAP, WRAP), dp(context, 2)));
        bubble.addView(text, BrowtherIntroUi.linear(MATCH, WRAP));
        return bubble;
    }

    /**
     * Ce que devient le lien. ⚠️ Ça doit ressembler à un <b>navigateur</b> : en-tête nommé, barre
     * d'adresse avec son cadenas, page en dessous, et le détail de ce que Browther vient de retirer.
     * ⚠️ Le panneau doit se <b>détacher</b> de la conversation : surface plus élevée, liseré net,
     * ombre portée — même teinte des deux côtés, on ne voyait plus la limite.
     */
    private static View browserSheet(Context context) {
        LinearLayout sheet = BrowtherIntroUi.column(context);
        float radius = dpf(context, 20);
        GradientDrawable fill = BrowtherIntroUi.corners(BrowtherIntroUi.SURFACE, radius, radius, 0, 0);
        GradientDrawable border = BrowtherIntroUi.corners(Color.TRANSPARENT, radius, radius, 0, 0);
        border.setStroke(Math.max(1, dp(context, 1)), BrowtherIntroUi.withAlpha(Color.WHITE, 0.22f));
        LayerDrawable background = new LayerDrawable(new Drawable[] {fill, border});
        background.setLayerInsetBottom(1, -dp(context, 4));
        sheet.setBackground(background);
        sheet.setElevation(dpf(context, 20));
        sheet.setOutlineSpotShadowColor(BrowtherIntroUi.withAlpha(Color.BLACK, 0.9f));

        View handle = new View(context);
        handle.setBackground(BrowtherIntroUi.capsule(BrowtherIntroUi.withAlpha(Color.WHITE, 0.22f)));
        LinearLayout.LayoutParams handleParams = BrowtherIntroUi.linear(dp(context, 34), dp(context, 4));
        handleParams.gravity = Gravity.CENTER_HORIZONTAL;
        handleParams.topMargin = dp(context, 7);
        sheet.addView(handle, handleParams);

        LinearLayout header = BrowtherIntroUi.row(context, 8);
        header.setPadding(dp(context, 14), dp(context, 8), dp(context, 14), dp(context, 8));
        ImageView appIcon = new ImageView(context);
        appIcon.setImageBitmap(
                BrowtherIntroUi.decodeAsset(
                        context, BrowtherIntroUi.ASSETS + "browther-app-icon.png", dp(context, 19)));
        appIcon.setBackground(BrowtherIntroUi.rounded(Color.TRANSPARENT, dpf(context, 5)));
        appIcon.setClipToOutline(true);
        header.addView(appIcon, BrowtherIntroUi.linear(dp(context, 19), dp(context, 19)));
        header.addView(
                BrowtherIntroUi.text(context, R.string.browther_intro_demo_opened_in, 13,
                        BrowtherIntroUi.SEMIBOLD, BrowtherIntroUi.INK),
                new LinearLayout.LayoutParams(0, WRAP, 1f));
        header.addView(
                BrowtherIntroUi.glyph(context, R.drawable.browther_intro_glyph_xmark, 11,
                        BrowtherIntroUi.INK_SOFT));
        sheet.addView(header, BrowtherIntroUi.linear(MATCH, WRAP));

        // La barre d'adresse : le repère qui dit « navigateur » sans un mot.
        LinearLayout address = BrowtherIntroUi.row(context, 6);
        address.setPadding(dp(context, 10), 0, dp(context, 10), 0);
        address.setBackground(BrowtherIntroUi.rounded(BrowtherIntroUi.BACKGROUND, dpf(context, 9)));
        address.addView(
                BrowtherIntroUi.glyph(context, R.drawable.browther_intro_glyph_lock, 10,
                        BrowtherIntroUi.INK_SOFT));
        address.addView(
                BrowtherIntroUi.text(context, R.string.browther_intro_demo_site_name, 12,
                        BrowtherIntroUi.MEDIUM, BrowtherIntroUi.INK),
                new LinearLayout.LayoutParams(0, WRAP, 1f));
        address.addView(
                BrowtherIntroUi.glyph(context, R.drawable.shield_icon_toolbar, 13,
                        BrowtherIntroUi.HALAL_TEXT));
        LinearLayout.LayoutParams addressParams = BrowtherIntroUi.linear(MATCH, dp(context, 32));
        addressParams.leftMargin = dp(context, 12);
        addressParams.rightMargin = dp(context, 12);
        sheet.addView(address, addressParams);

        // Ce que Browther vient de faire, nommé : « 3 bloqués » ne dirait pas quoi, et ferait
        // disparaître les deux autres moteurs.
        LinearLayout stats = BrowtherIntroUi.row(context, 6);
        stats.addView(stat(context, R.drawable.shield_icon_toolbar, R.string.browther_intro_demo_stat_ads),
                new LinearLayout.LayoutParams(0, WRAP, 1f));
        stats.addView(stat(context, R.drawable.sawtunaa_icon_toolbar, R.string.browther_intro_demo_stat_music),
                new LinearLayout.LayoutParams(0, WRAP, 1f));
        stats.addView(stat(context, R.drawable.basarunaa_icon_toolbar, R.string.browther_intro_demo_stat_images),
                new LinearLayout.LayoutParams(0, WRAP, 1f));
        LinearLayout.LayoutParams statsParams = BrowtherIntroUi.linear(MATCH, WRAP);
        statsParams.leftMargin = dp(context, 12);
        statsParams.rightMargin = dp(context, 12);
        statsParams.topMargin = dp(context, 9);
        sheet.addView(stats, statsParams);

        LinearLayout page = BrowtherIntroUi.column(context);
        BrowtherIntroUi.spacing(page, 8);
        GradientDrawable hero =
                new GradientDrawable(
                        GradientDrawable.Orientation.TL_BR, new int[] {0xFFE7C9A0, 0xFFC98F5B});
        hero.setCornerRadius(dpf(context, 10));
        View heroView = new View(context);
        heroView.setBackground(hero);
        page.addView(heroView, BrowtherIntroUi.linear(MATCH, dp(context, 52)));
        for (float ratio : new float[] {0.7f, 1f, 0.85f}) {
            FrameLayout line = new FrameLayout(context);
            View capsule = new View(context);
            capsule.setBackground(BrowtherIntroUi.capsule(BrowtherIntroUi.withAlpha(Color.WHITE, 0.1f)));
            line.addView(capsule, BrowtherIntroUi.frame(MATCH, MATCH, Gravity.START));
            capsule.setPivotX(0);
            capsule.setScaleX(ratio);
            page.addView(line, BrowtherIntroUi.linear(MATCH, dp(context, 8)));
        }
        LinearLayout.LayoutParams pageParams = BrowtherIntroUi.linear(MATCH, WRAP);
        pageParams.leftMargin = dp(context, 12);
        pageParams.rightMargin = dp(context, 12);
        pageParams.topMargin = dp(context, 10);
        sheet.addView(page, pageParams);
        return sheet;
    }

    private static View stat(Context context, int iconId, int labelId) {
        LinearLayout column = BrowtherIntroUi.column(context);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        column.setPadding(dp(context, 4), dp(context, 7), dp(context, 4), dp(context, 7));
        column.setBackground(
                BrowtherIntroUi.rounded(
                        BrowtherIntroUi.withAlpha(BrowtherIntroUi.HALAL_TEXT, 0.12f), dpf(context, 10)));
        column.addView(BrowtherIntroUi.glyph(context, iconId, 14, BrowtherIntroUi.HALAL_TEXT));
        TextView label =
                BrowtherIntroUi.text(context, labelId, 9.5f, BrowtherIntroUi.SEMIBOLD,
                        BrowtherIntroUi.HALAL_TEXT);
        label.setGravity(Gravity.CENTER);
        BrowtherIntroUi.singleLine(label, 7, 9.5f);
        column.addView(label, BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 4)));
        return column;
    }
}
