/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;

import androidx.annotation.Nullable;

import com.google.android.material.bottomsheet.BottomSheetBehavior;
import com.google.android.material.bottomsheet.BottomSheetDialog;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.BrowtherReferralPresenter.Source;
import org.chromium.chrome.browser.browther_referral.core.ExtrasState;
import org.chromium.chrome.browser.browther_referral.core.ReferralDate;
import org.chromium.chrome.browser.browther_referral.core.ReferralInvitations;
import org.chromium.chrome.browser.browther_referral.core.ReferralProduct;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;
import org.chromium.chrome.browser.browther_referral.core.ReminderCase;

import java.time.Instant;

/**
 * Les feuilles du flow (1 J−10/J−3, 3 rappels, 8 invitation validée, 8 bis filleul validé) —
 * pendant de {@code ReferralSheetView} (iOS). Fermeture classique (§ 12.14, § 12.23) : croix,
 * glissé vers le bas, retour système.
 *
 * <p>⚠️ Elle s'ouvre EN GRAND : à mi-hauteur, le J−3 demandait un geste pour lire sa propre issue
 * (« … mais tu peux les garder à vie »), c'est-à-dire la moitié utile de l'écran (recette iOS du
 * 2026-09-22).
 */
public final class ReferralSheetDialog extends BottomSheetDialog {
    private final Activity mActivity;
    private final ReferralScreen mScreen;
    private final boolean mPreview;
    private final BrowtherReferralController mController = BrowtherReferralController.get();
    private final ReferralUi.Palette mPalette;

    public ReferralSheetDialog(Activity activity, ReferralScreen screen, boolean preview) {
        super(activity);
        mActivity = activity;
        mScreen = screen;
        mPreview = preview;
        mPalette = ReferralUi.palette(activity);
        setContentView(build());
    }

    @Override
    protected void onStart() {
        super.onStart();
        BottomSheetBehavior<FrameLayout> behavior = getBehavior();
        behavior.setSkipCollapsed(true);
        behavior.setState(BottomSheetBehavior.STATE_EXPANDED);
        // Le fond est celui de notre contenu (coins arrondis compris) : le conteneur de la
        // bibliothèque devient transparent.
        // ⚠️ Par son NOM : Chromium ne génère pas `com.google.android.material.R`, et l'aperçu
        // hors Chromium n'a pas la bibliothèque Material (build OVH du 2026-09-24).
        int sheetId =
                getContext()
                        .getResources()
                        .getIdentifier("design_bottom_sheet", "id", getContext().getPackageName());
        View sheet = sheetId == 0 ? null : findViewById(sheetId);
        if (sheet != null) sheet.setBackgroundColor(Color.TRANSPARENT);
        // Une feuille : ses boutons sont en bas, les toasts montent (§ 11.6).
        BrowtherReferralPresenter.sheetShown(this);
        if (mScreen.kind == ReferralScreen.Kind.VALIDATED
                || mScreen.kind == ReferralScreen.Kind.REFEREE_DONE) {
            View content = findViewById(android.R.id.content);
            if (content != null) ReferralUi.success(content);
        }
    }

    @Override
    protected void onStop() {
        BrowtherReferralPresenter.sheetHidden(this);
        super.onStop();
    }

    private String s(String key) {
        return ReferralStrings.get(getContext(), key);
    }

    private void action(String name) {
        mController.note(
                "paywall_action", mPreview, "screen", mScreen.analyticsName(), "action", name);
    }

    /** Ferme la feuille PUIS ouvre l'écran Parrainage (§ 12.15). */
    private void openHome() {
        dismiss();
        BrowtherReferralPresenter.presentHome(mActivity, Source.FLOW);
    }

    /**
     * Ferme la feuille PUIS ouvre les trois façons — depuis une feuille qu'on pouvait fermer : une
     * fenêtre ORDINAIRE (§ 12.16, précisé le 2026-09-21).
     */
    private void openSupport() {
        dismiss();
        BrowtherReferralPresenter.present(
                mActivity, ReferralScreen.support(false), Source.FLOW, mPreview);
    }

    private View build() {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        FrameLayout root = new FrameLayout(context);
        GradientDrawable background = new GradientDrawable();
        float radius = ReferralUi.dp(context, 20);
        background.setCornerRadii(new float[] {radius, radius, radius, radius, 0, 0, 0, 0});
        background.setColor(p.screen);
        root.setBackground(background);

        ScrollView scroll = new ScrollView(context);
        // 🔴 § 12.38 : un fond explicite sur le conteneur du défilement.
        scroll.setBackgroundColor(p.screen);
        LinearLayout column = ReferralUi.column(context);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        column.setBackgroundColor(p.screen);
        int padH = ReferralUi.dp(context, 22);
        column.setPadding(padH, ReferralUi.dp(context, 28), padH, ReferralUi.dp(context, 20));
        // 🔴 Les boutons sont ÉPINGLÉS en bas, le texte défile au-dessus : sur un petit écran, le
        // J−3 poussait « Soutenir dev&din » et « Plus tard » sous le pli, et la personne ne voyait
        // qu'un texte à fermer (recette device du 2026-09-27, Huawei P20). Même grammaire que les
        // fenêtres plein écran (§ 12.26 : contenu au-dessus, boutons EN BAS).
        mFooter = ReferralUi.column(context);
        mFooter.setGravity(Gravity.CENTER_HORIZONTAL);
        mFooter.setBackgroundColor(p.screen);
        mFooter.setPadding(padH, ReferralUi.dp(context, 10), padH, ReferralUi.dp(context, 14));
        fill(column);
        scroll.addView(column, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));
        LinearLayout stack = ReferralUi.column(context);
        stack.setBackgroundColor(p.screen);
        // Poids 1 : le défilement prend ce qui reste une fois le pied mesuré, jamais plus.
        stack.addView(scroll, new LinearLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP, 1));
        if (mFooter.getChildCount() > 0) {
            View rule = new View(context);
            rule.setBackgroundColor(p.line);
            stack.addView(rule, ReferralUi.linear(ReferralUi.MATCH, 1));
            stack.addView(mFooter, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        }
        root.addView(stack, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));

        ImageView close = ReferralUi.glyph(context, R.drawable.browther_intro_glyph_xmark, 15, p.text2);
        int size = ReferralUi.dp(context, 44);
        int pad = (size - ReferralUi.dp(context, 15)) / 2;
        close.setPadding(pad, pad, pad, pad);
        close.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        close.setContentDescription(s("common.close"));
        close.setOnClickListener(v -> dismiss());
        FrameLayout.LayoutParams closeParams =
                ReferralUi.frame(size, size, Gravity.TOP | Gravity.END);
        closeParams.setMargins(0, ReferralUi.dp(context, 6), ReferralUi.dp(context, 6), 0);
        root.addView(close, closeParams);
        return root;
    }

    /** Un bouton (ce qui se touche) va dans le pied épinglé ; le reste dans le texte qui défile. */
    private @Nullable LinearLayout mFooter;

    private void add(LinearLayout column, View view) {
        if (view.isClickable() && mFooter != null) column = mFooter;
        if (column.getChildCount() > 0) ReferralUi.gap(column, column == mFooter ? 6 : 16);
        if (view.getLayoutParams() == null) {
            view.setLayoutParams(ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        }
        column.addView(view);
    }

    private void fill(LinearLayout column) {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        switch (mScreen.kind) {
            case ENDING:
                {
                    int days = mScreen.daysLeft;
                    add(column, ReferralUi.roundIcon(context, p, R.drawable.browther_referral_glyph_hourglass, ReferralUi.Tone.GOLD, 56));
                    add(column, ReferralUi.title(context, p, ReferralStrings.plural(context, "ending.title", days)));
                    add(column, ReferralUi.hook(context, p, s("ending.hook")));
                    add(column, ReferralUi.featureList(context, p, ExtrasState.soon(days), false));
                    add(column, ReferralUi.body(context, p, s("ending.body")));
                    add(
                            column,
                            ReferralUi.primaryButton(
                                    context,
                                    p,
                                    s("locked.cta"),
                                    s("ending.supportSub"),
                                    0,
                                    () -> {
                                        action("support");
                                        openSupport();
                                    }));
                    add(
                            column,
                            ReferralUi.textExit(
                                    context,
                                    p,
                                    s("welcome.later"),
                                    false,
                                    false,
                                    () -> {
                                        action("later");
                                        dismiss();
                                    }));
                    break;
                }
            case REMINDER:
                {
                    ReminderCase reminderCase = mScreen.reminderCase;
                    add(column, ReferralUi.roundIcon(context, p, R.drawable.browther_referral_glyph_bell, ReferralUi.Tone.GOLD, 56));
                    add(column, ReferralUi.title(context, p, reminderTitle(reminderCase, mScreen.daysLeft)));
                    add(column, ReferralUi.body(context, p, reminderBody(reminderCase)));
                    add(
                            column,
                            ReferralUi.primaryButton(
                                    context,
                                    p,
                                    alreadyInvited() ? s("invite.another") : s("announce.invite"),
                                    null,
                                    0,
                                    () -> {
                                        action("invite");
                                        openHome();
                                    }));
                    add(
                            column,
                            ReferralUi.textExit(
                                    context,
                                    p,
                                    s("welcome.later"),
                                    false,
                                    false,
                                    () -> {
                                        action("later");
                                        dismiss();
                                    }));
                    break;
                }
            case VALIDATED:
                add(
                        column,
                        ReferralUi.roundIcon(
                                context,
                                p,
                                mScreen.lifetime
                                        ? R.drawable.browther_referral_glyph_infinity
                                        : R.drawable.browther_referral_glyph_seal,
                                ReferralUi.Tone.GREEN,
                                64));
                add(column, ReferralUi.eyebrow(context, p, s("notice.eyebrow")));
                add(column, ReferralUi.title(context, p, s("notice.title")));
                add(column, ReferralUi.hook(context, p, validatedBody()));
                add(
                        column,
                        ReferralUi.body(
                                context,
                                p,
                                ReferralStrings.plural(
                                        context, "notice.why", ReferralProduct.validationTargetDays)));
                add(column, ReferralUi.primaryButton(context, p, s("notice.see"), null, 0, this::openHome));
                break;
            case REFEREE_DONE:
                add(column, ReferralUi.roundIcon(context, p, R.drawable.browther_referral_glyph_heart, ReferralUi.Tone.GREEN, 64));
                add(column, ReferralUi.eyebrow(context, p, s("notice.eyebrow")));
                add(column, ReferralUi.title(context, p, s("referee.noticeTitle")));
                add(column, ReferralUi.hook(context, p, s("referee.noticeBody")));
                add(
                        column,
                        ReferralUi.body(
                                context,
                                p,
                                ReferralStrings.plural(
                                        context,
                                        "referee.noticeWhy",
                                        ReferralProduct.validationTargetDays)));
                add(
                        column,
                        ReferralUi.primaryButton(
                                context, p, s("referee.inviteToo"), null, 0, this::openHome));
                break;
            default:
                break;
        }
    }

    /**
     * ⭐ « Inviter un AUTRE proche » dès qu'une invitation a porté : proposer « Inviter un proche »
     * à qui l'a déjà fait efface son geste. ⚠️ Les installées et les validées, ⛔ pas les {@code
     * sent} : envoyer un lien n'est pas encore avoir invité quelqu'un.
     */
    private boolean alreadyInvited() {
        ReferralStatus known = mController.known();
        if (known == null) return false;
        return known.invitations.installed + known.invitations.validated > 0;
    }

    private String reminderTitle(@Nullable ReminderCase reminderCase, int days) {
        Context context = getContext();
        if (reminderCase == ReminderCase.EARNED_MONTHS_ENDING) {
            return ReferralStrings.plural(context, "reminder.monthsTitle", days);
        }
        if (reminderCase == ReminderCase.SUBSCRIPTION_CANCELLED) {
            return ReferralStrings.plural(context, "reminder.subscriptionTitle", days);
        }
        return ReferralStrings.plural(context, "reminder.featuresTitle", days);
    }

    private String reminderBody(@Nullable ReminderCase reminderCase) {
        Context context = getContext();
        ReferralStatus known = mController.known();
        if (reminderCase == null) return s("reminder.months");
        switch (reminderCase) {
            case NONE_OPENED:
                return s("reminder.noneOpened");
            case IN_PROGRESS:
                {
                    Integer closest =
                            known == null
                                    ? null
                                    : ReferralInvitations.closestDaysLeft(known.invitations.items);
                    return closest == null
                            ? s("reminder.inProgress")
                            : ReferralStrings.plural(context, "reminder.inProgressCount", closest);
                }
            case EARNED_MONTHS_ENDING:
                {
                    // Le slot `{left}` lu dans `milestones.next.remaining` ; sans jalon à venir,
                    // la phrase s'arrête. ⭐ Le texte NOMME le gain — ⛔ jamais « palier suivant ».
                    ReferralStatus.Milestones.Next next =
                            known == null ? null : known.milestones.next;
                    if (next == null) return s("reminder.months");
                    if (next.lifetime) {
                        return ReferralStrings.plural(context, "reminder.monthsNextLife", next.remaining);
                    }
                    // ⚠️ `{bonus}` est un slot de plus : `plural` ne remplit que `{count}`.
                    return ReferralStrings.fill(
                            ReferralStrings.plural(context, "reminder.monthsNext", next.remaining),
                            "bonus",
                            String.valueOf(next.bonusMonths));
                }
            case SUBSCRIPTION_CANCELLED:
            default:
                return s("reminder.subscription");
        }
    }

    private String validatedBody() {
        Context context = getContext();
        if (mScreen.lifetime) return s("notice.bodyLifetime");
        Instant date = ReferralDate.parse(mScreen.until);
        if (date == null) {
            return ReferralStrings.plural(context, "notice.bodyNoDate", mScreen.months);
        }
        return ReferralStrings.fill(
                ReferralStrings.plural(context, "notice.body", mScreen.months),
                "date",
                ReferralFormat.date(context, date, false));
    }
}
