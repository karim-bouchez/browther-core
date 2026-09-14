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
import android.graphics.Color;
import android.graphics.Outline;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.chromium.chrome.R;

/**
 * 6 · Canaux dev&din. Browther replacé dans l'écosystème, et les deux canaux où l'on annonce ce qui
 * sort. Sur un téléphone, les boutons ouvrent directement les apps (pas de QR comme sur desktop).
 *
 * <p>Les deux notifications du desktop ne sont pas reprises : sur iPhone elles ont été retirées faute
 * de place (Karim, 2026-09-13), et un téléphone Android n'en a pas davantage.
 */
final class BrowtherIntroChannelsStep extends BrowtherIntroStepView {
    BrowtherIntroChannelsStep(Context context, BrowtherIntroModel model) {
        super(context, model);
        boolean soon = model.isEarlyAccess();
        Slots slots =
                template(
                        null,
                        context.getString(
                                soon
                                        ? R.string.browther_intro_channels_soon_title
                                        : R.string.browther_follow_channels_title),
                        context.getString(
                                soon
                                        ? R.string.browther_intro_channels_soon_description
                                        : R.string.browther_follow_channels_description),
                        null);

        // Le visuel de l'écosystème. ⛔ Rien par-dessus.
        ImageView visual = new ImageView(context);
        visual.setAdjustViewBounds(true);
        visual.setScaleType(ImageView.ScaleType.FIT_CENTER);
        visual.setImageBitmap(
                BrowtherIntroUi.decodeAsset(
                        context,
                        BrowtherIntroUi.ASSETS + visualName(context),
                        context.getResources().getDisplayMetrics().widthPixels));
        final float radius = dpf(context, 18);
        visual.setOutlineProvider(
                new ViewOutlineProvider() {
                    @Override
                    public void getOutline(View view, Outline outline) {
                        // Arrondi sur l'image elle-même, pas sur la boîte de la vue.
                        android.graphics.drawable.Drawable drawable =
                                ((ImageView) view).getDrawable();
                        if (drawable == null) {
                            outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
                            return;
                        }
                        float scale =
                                Math.min(
                                        (float) view.getWidth() / drawable.getIntrinsicWidth(),
                                        (float) view.getHeight() / drawable.getIntrinsicHeight());
                        int w = Math.round(drawable.getIntrinsicWidth() * scale);
                        int h = Math.round(drawable.getIntrinsicHeight() * scale);
                        int left = (view.getWidth() - w) / 2;
                        int top = (view.getHeight() - h) / 2;
                        outline.setRoundRect(left, top, left + w, top + h, radius);
                    }
                });
        visual.setClipToOutline(true);
        visual.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        slots.mScene.addView(visual, BrowtherIntroUi.frame(MATCH, MATCH, Gravity.CENTER));

        slots.mActions.addView(
                channelButton(context, BrowtherIntroModel.Channel.WHATSAPP,
                        R.string.browther_follow_channels_whatsapp, 0xFF25D366, "channel-whatsapp.png"));
        slots.mActions.addView(
                channelButton(context, BrowtherIntroModel.Channel.TELEGRAM,
                        R.string.browther_follow_channels_telegram, 0xFF229ED9, "channel-telegram.png"));

        TextView same =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_channels_same_content,
                        13,
                        BrowtherIntroUi.REGULAR,
                        BrowtherIntroUi.INK_TERTIARY);
        same.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams sameParams = BrowtherIntroUi.linear(MATCH, WRAP);
        sameParams.topMargin = dp(context, 2);
        // Cette mention appartient aux deux boutons du dessus : l'espace au-dessous le dit.
        sameParams.bottomMargin = dp(context, 14);
        slots.mActions.addView(same, sameParams);

        BrowtherIntroWidgets.Button start =
                new BrowtherIntroWidgets.Button(
                        context,
                        R.string.browther_intro_start_browsing,
                        BrowtherIntroWidgets.Button.Style.OUTLINE);
        start.setOnClickListener(v -> mModel.finish());
        slots.mActions.addView(start);
    }

    @Override
    void bind(boolean animated) {}

    /** Le visuel existe en français, en anglais et en arabe — celui de la langue de l'appareil. */
    private static String visualName(Context context) {
        String language = context.getResources().getConfiguration().getLocales().get(0).getLanguage();
        if ("fr".equals(language)) return "devndin-channels-fr.png";
        if ("ar".equals(language)) return "devndin-channels-ar.png";
        return "devndin-channels-en.png";
    }

    /** Bouton plein aux couleurs du service, avec son vrai logo. */
    private View channelButton(
            Context context, BrowtherIntroModel.Channel channel, int labelId, int color, String logo) {
        LinearLayout row = BrowtherIntroUi.row(context, 12);
        row.setPadding(dp(context, 14), 0, dp(context, 14), 0);
        row.setBackground(BrowtherIntroUi.rounded(color, dpf(context, 14)));
        row.setClickable(true);
        row.setFocusable(true);
        row.setOnClickListener(v -> mModel.openChannel(channel));

        FrameLayout circle = new FrameLayout(context);
        circle.setBackground(BrowtherIntroUi.capsule(Color.WHITE));
        ImageView image = new ImageView(context);
        image.setScaleType(ImageView.ScaleType.FIT_CENTER);
        image.setImageBitmap(
                BrowtherIntroUi.decodeAsset(context, BrowtherIntroUi.ASSETS + logo, dp(context, 22)));
        circle.addView(image, BrowtherIntroUi.frame(dp(context, 22), dp(context, 22), Gravity.CENTER));
        row.addView(circle, BrowtherIntroUi.linear(dp(context, 30), dp(context, 30)));

        TextView label =
                BrowtherIntroUi.text(context, labelId, 16, BrowtherIntroUi.SEMIBOLD, Color.WHITE);
        row.addView(label, new LinearLayout.LayoutParams(0, WRAP, 1f));
        row.setContentDescription(label.getText());

        ImageView chevron =
                BrowtherIntroUi.glyph(
                        context,
                        R.drawable.browther_intro_glyph_chevron_right,
                        13,
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.8f));
        row.addView(chevron);
        row.setLayoutParams(BrowtherIntroUi.linear(MATCH, dp(context, 54)));
        return row;
    }
}
