/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;

import org.chromium.chrome.R;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Les textes du parrainage, par CLÉ du pool commun ({@code private/assets/ios-referral-strings/}).
 *
 * <p>⛔ GÉNÉRÉ par {@code private/assets/gen-android-browther-xtb.py --apply} (avec le bloc {@code
 * IDS_BROWTHER_REFERRAL_*} du {@code .grd} et les {@code .xtb}) : ne pas éditer à la main. Un
 * écran demande {@code get(ctx, "home.title")}, jamais un {@code R.string} : la clé est la même sur
 * les trois plateformes.
 *
 * <p>🔴 Pluriels : {@link #plural} choisit la catégorie CLDR de la langue AFFICHÉE ({@link
 * #category}, portage de {@code Strings.BrowtherReferral.category(_:language:)} en Swift, étendu aux
 * langues que seul le desktop avait — mêmes réponses que {@code Intl.PluralRules} pour un nombre
 * entier). ⛔ Jamais « si 1 sinon ».
 */
public final class ReferralStrings {
    /** L'ordre des colonnes de {@link #PLURALS}. */
    private static final String[] CATEGORIES = {"zero", "one", "two", "few", "many", "other"};

    private static final Map<String, Integer> SIMPLE = new HashMap<>();
    private static final Map<String, int[]> PLURALS = new HashMap<>();

    static {
        SIMPLE.put("announce.body", R.string.browther_referral_announce_body);
        SIMPLE.put("announce.invite", R.string.browther_referral_announce_invite);
        SIMPLE.put("announce.inviteSub", R.string.browther_referral_announce_invite_sub);
        SIMPLE.put("announce.later", R.string.browther_referral_announce_later);
        SIMPLE.put("announce.title", R.string.browther_referral_announce_title);
        SIMPLE.put("announceLater.body", R.string.browther_referral_announce_later_body);
        SIMPLE.put("announceLater.bodyNoDate", R.string.browther_referral_announce_later_body_no_date);
        SIMPLE.put("announceLater.title", R.string.browther_referral_announce_later_title);
        SIMPLE.put("announceLater.where", R.string.browther_referral_announce_later_where);
        SIMPLE.put("billing.alreadyBody", R.string.browther_referral_billing_already_body);
        SIMPLE.put("billing.alreadyTitle", R.string.browther_referral_billing_already_title);
        SIMPLE.put("billing.body", R.string.browther_referral_billing_body);
        SIMPLE.put("billing.ctaMonth", R.string.browther_referral_billing_cta_month);
        SIMPLE.put("billing.ctaYear", R.string.browther_referral_billing_cta_year);
        SIMPLE.put("billing.ends", R.string.browther_referral_billing_ends);
        SIMPLE.put("billing.eyebrow", R.string.browther_referral_billing_eyebrow);
        SIMPLE.put("billing.failed", R.string.browther_referral_billing_failed);
        SIMPLE.put("billing.month", R.string.browther_referral_billing_month);
        SIMPLE.put("billing.monthSub", R.string.browther_referral_billing_month_sub);
        SIMPLE.put("billing.renews", R.string.browther_referral_billing_renews);
        SIMPLE.put("billing.retry", R.string.browther_referral_billing_retry);
        SIMPLE.put("billing.title", R.string.browther_referral_billing_title);
        SIMPLE.put("billing.unavailable", R.string.browther_referral_billing_unavailable);
        SIMPLE.put("billing.year", R.string.browther_referral_billing_year);
        SIMPLE.put("billing.yearBadge", R.string.browther_referral_billing_year_badge);
        SIMPLE.put("billing.yearSub", R.string.browther_referral_billing_year_sub);
        SIMPLE.put("card.codeHead", R.string.browther_referral_card_code_head);
        SIMPLE.put("card.copied", R.string.browther_referral_card_copied);
        SIMPLE.put("card.copy", R.string.browther_referral_card_copy);
        SIMPLE.put("common.close", R.string.browther_referral_common_close);
        SIMPLE.put("ending.body", R.string.browther_referral_ending_body);
        SIMPLE.put("ending.hook", R.string.browther_referral_ending_hook);
        SIMPLE.put("ending.supportSub", R.string.browther_referral_ending_support_sub);
        SIMPLE.put("features.essential.blur", R.string.browther_referral_features_essential_blur);
        SIMPLE.put("features.essential.browsing", R.string.browther_referral_features_essential_browsing);
        SIMPLE.put("features.essential.shields", R.string.browther_referral_features_essential_shields);
        SIMPLE.put("features.essentialLine", R.string.browther_referral_features_essential_line);
        SIMPLE.put("features.extras.musicRemoval", R.string.browther_referral_features_extras_music_removal);
        SIMPLE.put("features.extrasHead", R.string.browther_referral_features_extras_head);
        SIMPLE.put("features.freeHead", R.string.browther_referral_features_free_head);
        SIMPLE.put("features.gainHead", R.string.browther_referral_features_gain_head);
        SIMPLE.put("features.included", R.string.browther_referral_features_included);
        SIMPLE.put("features.offered", R.string.browther_referral_features_offered);
        SIMPLE.put("features.paused", R.string.browther_referral_features_paused);
        SIMPLE.put("features.until", R.string.browther_referral_features_until);
        SIMPLE.put("gauge.a11y", R.string.browther_referral_gauge_a11y);
        SIMPLE.put("gauge.bonus", R.string.browther_referral_gauge_bonus);
        SIMPLE.put("gauge.help", R.string.browther_referral_gauge_help);
        SIMPLE.put("gauge.if", R.string.browther_referral_gauge_if);
        SIMPLE.put("gauge.ifElastic", R.string.browther_referral_gauge_if_elastic);
        SIMPLE.put("gauge.lifeReached", R.string.browther_referral_gauge_life_reached);
        SIMPLE.put("gauge.lifeTitle", R.string.browther_referral_gauge_life_title);
        SIMPLE.put("gauge.lifetime", R.string.browther_referral_gauge_lifetime);
        SIMPLE.put("gauge.restIf", R.string.browther_referral_gauge_rest_if);
        SIMPLE.put("gauge.restThen", R.string.browther_referral_gauge_rest_then);
        SIMPLE.put("gauge.then", R.string.browther_referral_gauge_then);
        SIMPLE.put("gauge.thenElastic", R.string.browther_referral_gauge_then_elastic);
        SIMPLE.put("gauge.tickLifetime", R.string.browther_referral_gauge_tick_lifetime);
        SIMPLE.put("gift.ask", R.string.browther_referral_gift_ask);
        SIMPLE.put("gift.body", R.string.browther_referral_gift_body);
        SIMPLE.put("gift.bodyAgain", R.string.browther_referral_gift_body_again);
        SIMPLE.put("gift.title", R.string.browther_referral_gift_title);
        SIMPLE.put("gift.titleAgain", R.string.browther_referral_gift_title_again);
        SIMPLE.put("gift.until", R.string.browther_referral_gift_until);
        SIMPLE.put("grace.body", R.string.browther_referral_grace_body);
        SIMPLE.put("grace.status", R.string.browther_referral_grace_status);
        SIMPLE.put("grace.title", R.string.browther_referral_grace_title);
        SIMPLE.put("home.accountHead", R.string.browther_referral_home_account_head);
        SIMPLE.put("home.asReferee", R.string.browther_referral_home_as_referee);
        SIMPLE.put("home.coverA", R.string.browther_referral_home_cover_a);
        SIMPLE.put("home.coverLifetime", R.string.browther_referral_home_cover_lifetime);
        SIMPLE.put("home.coverOpen", R.string.browther_referral_home_cover_open);
        SIMPLE.put("home.coverPaid", R.string.browther_referral_home_cover_paid);
        SIMPLE.put("home.coverPaused", R.string.browther_referral_home_cover_paused);
        SIMPLE.put("home.coverUntil", R.string.browther_referral_home_cover_until);
        SIMPLE.put("home.empty", R.string.browther_referral_home_empty);
        SIMPLE.put("home.emptyHint", R.string.browther_referral_home_empty_hint);
        SIMPLE.put("home.legend", R.string.browther_referral_home_legend);
        SIMPLE.put("home.linkOpens", R.string.browther_referral_home_link_opens);
        SIMPLE.put("home.listHead", R.string.browther_referral_home_list_head);
        SIMPLE.put("home.retry", R.string.browther_referral_home_retry);
        SIMPLE.put("home.tabs.code", R.string.browther_referral_home_tabs_code);
        SIMPLE.put("home.tabs.invitations", R.string.browther_referral_home_tabs_invitations);
        SIMPLE.put("home.tabs.invite", R.string.browther_referral_home_tabs_invite);
        SIMPLE.put("home.tabs.support", R.string.browther_referral_home_tabs_support);
        SIMPLE.put("home.title", R.string.browther_referral_home_title);
        SIMPLE.put("home.unreachable", R.string.browther_referral_home_unreachable);
        SIMPLE.put("home.whatExtras", R.string.browther_referral_home_what_extras);
        SIMPLE.put("home.whyPaused", R.string.browther_referral_home_why_paused);
        SIMPLE.put("invitations.inProgress", R.string.browther_referral_invitations_in_progress);
        SIMPLE.put("invitations.validated", R.string.browther_referral_invitations_validated);
        SIMPLE.put("invite.another", R.string.browther_referral_invite_another);
        SIMPLE.put("invite.back", R.string.browther_referral_invite_back);
        SIMPLE.put("invite.closeAfterShare", R.string.browther_referral_invite_close_after_share);
        SIMPLE.put("invite.eyebrow", R.string.browther_referral_invite_eyebrow);
        SIMPLE.put("invite.share", R.string.browther_referral_invite_share);
        SIMPLE.put("locked.body", R.string.browther_referral_locked_body);
        SIMPLE.put("locked.cta", R.string.browther_referral_locked_cta);
        SIMPLE.put("locked.musicRemoval", R.string.browther_referral_locked_music_removal);
        SIMPLE.put("locked.unlock", R.string.browther_referral_locked_unlock);
        SIMPLE.put("menu.invite", R.string.browther_referral_menu_invite);
        SIMPLE.put("notice.bodyLifetime", R.string.browther_referral_notice_body_lifetime);
        SIMPLE.put("notice.eyebrow", R.string.browther_referral_notice_eyebrow);
        SIMPLE.put("notice.see", R.string.browther_referral_notice_see);
        SIMPLE.put("notice.title", R.string.browther_referral_notice_title);
        SIMPLE.put("panel.covered", R.string.browther_referral_panel_covered);
        SIMPLE.put("panel.coveredUntil", R.string.browther_referral_panel_covered_until);
        SIMPLE.put("panel.extraBadge", R.string.browther_referral_panel_extra_badge);
        SIMPLE.put("panel.keepForLife", R.string.browther_referral_panel_keep_for_life);
        SIMPLE.put("panel.pausedLine", R.string.browther_referral_panel_paused_line);
        SIMPLE.put("paused.body", R.string.browther_referral_paused_body);
        SIMPLE.put("paused.foot", R.string.browther_referral_paused_foot);
        SIMPLE.put("paused.title", R.string.browther_referral_paused_title);
        SIMPLE.put("redeem.body", R.string.browther_referral_redeem_body);
        SIMPLE.put("redeem.head", R.string.browther_referral_redeem_head);
        SIMPLE.put("redeem.inputError.alphabet", R.string.browther_referral_redeem_input_error_alphabet);
        SIMPLE.put("redeem.inputError.length", R.string.browther_referral_redeem_input_error_length);
        SIMPLE.put("redeem.paste", R.string.browther_referral_redeem_paste);
        SIMPLE.put("redeem.placeholder", R.string.browther_referral_redeem_placeholder);
        SIMPLE.put("redeem.refusal.already_redeemed", R.string.browther_referral_redeem_refusal_already_redeemed);
        SIMPLE.put("redeem.refusal.same_device", R.string.browther_referral_redeem_refusal_same_device);
        SIMPLE.put("redeem.refusal.self", R.string.browther_referral_redeem_refusal_self);
        SIMPLE.put("redeem.refusal.unavailable", R.string.browther_referral_redeem_refusal_unavailable);
        SIMPLE.put("redeem.refusal.unknown_code", R.string.browther_referral_redeem_refusal_unknown_code);
        SIMPLE.put("redeem.refusal.wrong_product", R.string.browther_referral_redeem_refusal_wrong_product);
        SIMPLE.put("redeem.validate", R.string.browther_referral_redeem_validate);
        SIMPLE.put("redeem.validatedLine", R.string.browther_referral_redeem_validated_line);
        SIMPLE.put("referee.done", R.string.browther_referral_referee_done);
        SIMPLE.put("referee.inviteToo", R.string.browther_referral_referee_invite_too);
        SIMPLE.put("referee.noticeBody", R.string.browther_referral_referee_notice_body);
        SIMPLE.put("referee.noticeTitle", R.string.browther_referral_referee_notice_title);
        SIMPLE.put("referee.setDefault", R.string.browther_referral_referee_set_default);
        SIMPLE.put("referee.title", R.string.browther_referral_referee_title);
        SIMPLE.put("reminder.inProgress", R.string.browther_referral_reminder_in_progress);
        SIMPLE.put("reminder.months", R.string.browther_referral_reminder_months);
        SIMPLE.put("reminder.noneOpened", R.string.browther_referral_reminder_none_opened);
        SIMPLE.put("reminder.subscription", R.string.browther_referral_reminder_subscription);
        SIMPLE.put("settings.news", R.string.browther_referral_settings_news);
        SIMPLE.put("settings.subtitle", R.string.browther_referral_settings_subtitle);
        SIMPLE.put("share.copied", R.string.browther_referral_share_copied);
        SIMPLE.put("share.message", R.string.browther_referral_share_message);
        SIMPLE.put("support.money", R.string.browther_referral_support_money);
        SIMPLE.put("support.none", R.string.browther_referral_support_none);
        SIMPLE.put("support.or", R.string.browther_referral_support_or);
        SIMPLE.put("support.title", R.string.browther_referral_support_title);
        SIMPLE.put("thanks.bodyActive", R.string.browther_referral_thanks_body_active);
        SIMPLE.put("thanks.bodyPending", R.string.browther_referral_thanks_body_pending);
        SIMPLE.put("thanks.title", R.string.browther_referral_thanks_title);
        SIMPLE.put("welcome.later", R.string.browther_referral_welcome_later);
        PLURALS.put("ending.title", new int[] {R.string.browther_referral_ending_title_zero, R.string.browther_referral_ending_title_one, R.string.browther_referral_ending_title_two, R.string.browther_referral_ending_title_few, R.string.browther_referral_ending_title_many, R.string.browther_referral_ending_title_other});
        PLURALS.put("features.soon", new int[] {R.string.browther_referral_features_soon_zero, R.string.browther_referral_features_soon_one, R.string.browther_referral_features_soon_two, R.string.browther_referral_features_soon_few, R.string.browther_referral_features_soon_many, R.string.browther_referral_features_soon_other});
        PLURALS.put("gauge.lifeSub", new int[] {R.string.browther_referral_gauge_life_sub_zero, R.string.browther_referral_gauge_life_sub_one, R.string.browther_referral_gauge_life_sub_two, R.string.browther_referral_gauge_life_sub_few, R.string.browther_referral_gauge_life_sub_many, R.string.browther_referral_gauge_life_sub_other});
        PLURALS.put("gauge.months", new int[] {R.string.browther_referral_gauge_months_zero, R.string.browther_referral_gauge_months_one, R.string.browther_referral_gauge_months_two, R.string.browther_referral_gauge_months_few, R.string.browther_referral_gauge_months_many, R.string.browther_referral_gauge_months_other});
        PLURALS.put("gauge.now", new int[] {R.string.browther_referral_gauge_now_zero, R.string.browther_referral_gauge_now_one, R.string.browther_referral_gauge_now_two, R.string.browther_referral_gauge_now_few, R.string.browther_referral_gauge_now_many, R.string.browther_referral_gauge_now_other});
        PLURALS.put("gauge.tickBonus", new int[] {R.string.browther_referral_gauge_tick_bonus_zero, R.string.browther_referral_gauge_tick_bonus_one, R.string.browther_referral_gauge_tick_bonus_two, R.string.browther_referral_gauge_tick_bonus_few, R.string.browther_referral_gauge_tick_bonus_many, R.string.browther_referral_gauge_tick_bonus_other});
        PLURALS.put("gauge.unit", new int[] {R.string.browther_referral_gauge_unit_zero, R.string.browther_referral_gauge_unit_one, R.string.browther_referral_gauge_unit_two, R.string.browther_referral_gauge_unit_few, R.string.browther_referral_gauge_unit_many, R.string.browther_referral_gauge_unit_other});
        PLURALS.put("gauge.unitInv", new int[] {R.string.browther_referral_gauge_unit_inv_zero, R.string.browther_referral_gauge_unit_inv_one, R.string.browther_referral_gauge_unit_inv_two, R.string.browther_referral_gauge_unit_inv_few, R.string.browther_referral_gauge_unit_inv_many, R.string.browther_referral_gauge_unit_inv_other});
        PLURALS.put("home.progress", new int[] {R.string.browther_referral_home_progress_zero, R.string.browther_referral_home_progress_one, R.string.browther_referral_home_progress_two, R.string.browther_referral_home_progress_few, R.string.browther_referral_home_progress_many, R.string.browther_referral_home_progress_other});
        PLURALS.put("home.progressLife", new int[] {R.string.browther_referral_home_progress_life_zero, R.string.browther_referral_home_progress_life_one, R.string.browther_referral_home_progress_life_two, R.string.browther_referral_home_progress_life_few, R.string.browther_referral_home_progress_life_many, R.string.browther_referral_home_progress_life_other});
        PLURALS.put("home.progressToLife", new int[] {R.string.browther_referral_home_progress_to_life_zero, R.string.browther_referral_home_progress_to_life_one, R.string.browther_referral_home_progress_to_life_two, R.string.browther_referral_home_progress_to_life_few, R.string.browther_referral_home_progress_to_life_many, R.string.browther_referral_home_progress_to_life_other});
        PLURALS.put("invitations.milestone", new int[] {R.string.browther_referral_invitations_milestone_zero, R.string.browther_referral_invitations_milestone_one, R.string.browther_referral_invitations_milestone_two, R.string.browther_referral_invitations_milestone_few, R.string.browther_referral_invitations_milestone_many, R.string.browther_referral_invitations_milestone_other});
        PLURALS.put("invitations.months", new int[] {R.string.browther_referral_invitations_months_zero, R.string.browther_referral_invitations_months_one, R.string.browther_referral_invitations_months_two, R.string.browther_referral_invitations_months_few, R.string.browther_referral_invitations_months_many, R.string.browther_referral_invitations_months_other});
        PLURALS.put("invitations.rowInProgress", new int[] {R.string.browther_referral_invitations_row_in_progress_zero, R.string.browther_referral_invitations_row_in_progress_one, R.string.browther_referral_invitations_row_in_progress_two, R.string.browther_referral_invitations_row_in_progress_few, R.string.browther_referral_invitations_row_in_progress_many, R.string.browther_referral_invitations_row_in_progress_other});
        PLURALS.put("invitations.rowInProgressUnknown", new int[] {R.string.browther_referral_invitations_row_in_progress_unknown_zero, R.string.browther_referral_invitations_row_in_progress_unknown_one, R.string.browther_referral_invitations_row_in_progress_unknown_two, R.string.browther_referral_invitations_row_in_progress_unknown_few, R.string.browther_referral_invitations_row_in_progress_unknown_many, R.string.browther_referral_invitations_row_in_progress_unknown_other});
        PLURALS.put("invitations.rowValidated", new int[] {R.string.browther_referral_invitations_row_validated_zero, R.string.browther_referral_invitations_row_validated_one, R.string.browther_referral_invitations_row_validated_two, R.string.browther_referral_invitations_row_validated_few, R.string.browther_referral_invitations_row_validated_many, R.string.browther_referral_invitations_row_validated_other});
        PLURALS.put("invite.foot", new int[] {R.string.browther_referral_invite_foot_zero, R.string.browther_referral_invite_foot_one, R.string.browther_referral_invite_foot_two, R.string.browther_referral_invite_foot_few, R.string.browther_referral_invite_foot_many, R.string.browther_referral_invite_foot_other});
        PLURALS.put("notice.body", new int[] {R.string.browther_referral_notice_body_zero, R.string.browther_referral_notice_body_one, R.string.browther_referral_notice_body_two, R.string.browther_referral_notice_body_few, R.string.browther_referral_notice_body_many, R.string.browther_referral_notice_body_other});
        PLURALS.put("notice.bodyNoDate", new int[] {R.string.browther_referral_notice_body_no_date_zero, R.string.browther_referral_notice_body_no_date_one, R.string.browther_referral_notice_body_no_date_two, R.string.browther_referral_notice_body_no_date_few, R.string.browther_referral_notice_body_no_date_many, R.string.browther_referral_notice_body_no_date_other});
        PLURALS.put("notice.why", new int[] {R.string.browther_referral_notice_why_zero, R.string.browther_referral_notice_why_one, R.string.browther_referral_notice_why_two, R.string.browther_referral_notice_why_few, R.string.browther_referral_notice_why_many, R.string.browther_referral_notice_why_other});
        PLURALS.put("referee.hint", new int[] {R.string.browther_referral_referee_hint_zero, R.string.browther_referral_referee_hint_one, R.string.browther_referral_referee_hint_two, R.string.browther_referral_referee_hint_few, R.string.browther_referral_referee_hint_many, R.string.browther_referral_referee_hint_other});
        PLURALS.put("referee.meter", new int[] {R.string.browther_referral_referee_meter_zero, R.string.browther_referral_referee_meter_one, R.string.browther_referral_referee_meter_two, R.string.browther_referral_referee_meter_few, R.string.browther_referral_referee_meter_many, R.string.browther_referral_referee_meter_other});
        PLURALS.put("referee.noticeWhy", new int[] {R.string.browther_referral_referee_notice_why_zero, R.string.browther_referral_referee_notice_why_one, R.string.browther_referral_referee_notice_why_two, R.string.browther_referral_referee_notice_why_few, R.string.browther_referral_referee_notice_why_many, R.string.browther_referral_referee_notice_why_other});
        PLURALS.put("referee.progress", new int[] {R.string.browther_referral_referee_progress_zero, R.string.browther_referral_referee_progress_one, R.string.browther_referral_referee_progress_two, R.string.browther_referral_referee_progress_few, R.string.browther_referral_referee_progress_many, R.string.browther_referral_referee_progress_other});
        PLURALS.put("reminder.featuresTitle", new int[] {R.string.browther_referral_reminder_features_title_zero, R.string.browther_referral_reminder_features_title_one, R.string.browther_referral_reminder_features_title_two, R.string.browther_referral_reminder_features_title_few, R.string.browther_referral_reminder_features_title_many, R.string.browther_referral_reminder_features_title_other});
        PLURALS.put("reminder.inProgressCount", new int[] {R.string.browther_referral_reminder_in_progress_count_zero, R.string.browther_referral_reminder_in_progress_count_one, R.string.browther_referral_reminder_in_progress_count_two, R.string.browther_referral_reminder_in_progress_count_few, R.string.browther_referral_reminder_in_progress_count_many, R.string.browther_referral_reminder_in_progress_count_other});
        PLURALS.put("reminder.monthsNext", new int[] {R.string.browther_referral_reminder_months_next_zero, R.string.browther_referral_reminder_months_next_one, R.string.browther_referral_reminder_months_next_two, R.string.browther_referral_reminder_months_next_few, R.string.browther_referral_reminder_months_next_many, R.string.browther_referral_reminder_months_next_other});
        PLURALS.put("reminder.monthsNextLife", new int[] {R.string.browther_referral_reminder_months_next_life_zero, R.string.browther_referral_reminder_months_next_life_one, R.string.browther_referral_reminder_months_next_life_two, R.string.browther_referral_reminder_months_next_life_few, R.string.browther_referral_reminder_months_next_life_many, R.string.browther_referral_reminder_months_next_life_other});
        PLURALS.put("reminder.monthsTitle", new int[] {R.string.browther_referral_reminder_months_title_zero, R.string.browther_referral_reminder_months_title_one, R.string.browther_referral_reminder_months_title_two, R.string.browther_referral_reminder_months_title_few, R.string.browther_referral_reminder_months_title_many, R.string.browther_referral_reminder_months_title_other});
        PLURALS.put("reminder.subscriptionTitle", new int[] {R.string.browther_referral_reminder_subscription_title_zero, R.string.browther_referral_reminder_subscription_title_one, R.string.browther_referral_reminder_subscription_title_two, R.string.browther_referral_reminder_subscription_title_few, R.string.browther_referral_reminder_subscription_title_many, R.string.browther_referral_reminder_subscription_title_other});
        PLURALS.put("support.inviteCount", new int[] {R.string.browther_referral_support_invite_count_zero, R.string.browther_referral_support_invite_count_one, R.string.browther_referral_support_invite_count_two, R.string.browther_referral_support_invite_count_few, R.string.browther_referral_support_invite_count_many, R.string.browther_referral_support_invite_count_other});
        PLURALS.put("support.inviteSub", new int[] {R.string.browther_referral_support_invite_sub_zero, R.string.browther_referral_support_invite_sub_one, R.string.browther_referral_support_invite_sub_two, R.string.browther_referral_support_invite_sub_few, R.string.browther_referral_support_invite_sub_many, R.string.browther_referral_support_invite_sub_other});
    }

    private ReferralStrings() {}

    /**
     * Le texte d'une clé simple. 🔴 Une clé inconnue LÈVE (faute de frappe, clé exclue d'Android) :
     * elle doit se voir au premier affichage, ⛔ pas s'afficher en clé brute chez quelqu'un.
     */
    public static String get(Context context, String key) {
        Integer id = SIMPLE.get(key);
        if (id == null) {
            throw new IllegalArgumentException("Clé de parrainage inconnue sur Android : " + key);
        }
        return context.getString(id);
    }

    /** {@link #get} puis {@link #fill}. */
    public static String get(Context context, String key, Map<String, String> values) {
        return fill(get(context, key), values);
    }

    /**
     * Un texte au pluriel ({@code key} = la famille, sans {@code .one}/{@code .other}) : la forme
     * de la langue affichée, {@code {count}} remplacé par le nombre. Un nombre et son unité ne se
     * coupent jamais en fin de ligne (§ 12.26) : l'espace qui suit {@code {count}} devient
     * insécable, comme sur iOS.
     */
    public static String plural(Context context, String key, long count) {
        return plural(context, key, count, null);
    }

    /** {@link #plural} avec d'autres emplacements ({@code {bonus}}, {@code {date}}…). */
    public static String plural(Context context, String key, long count, Map<String, String> values) {
        int[] ids = PLURALS.get(key);
        if (ids == null) {
            throw new IllegalArgumentException("Pluriel de parrainage inconnu sur Android : " + key);
        }
        String category = category(count, language(context));
        int index = 0;
        while (!CATEGORIES[index].equals(category)) index++;
        String text = context.getString(ids[index]).replace("{count} ", "{count}\u00A0");
        Map<String, String> all = new HashMap<>();
        if (values != null) all.putAll(values);
        all.put("count", Long.toString(count));
        return fill(text, all);
    }

    /**
     * {@link #fill(String, Map)} en paires clé/valeur : {@code fill(texte, "date", d, "bonus", "3")}.
     */
    public static String fill(String text, String... keyValues) {
        if (keyValues.length % 2 != 0) {
            throw new IllegalArgumentException("fill() attend des paires clé/valeur");
        }
        Map<String, String> values = new HashMap<>();
        for (int i = 0; i < keyValues.length; i += 2) values.put(keyValues[i], keyValues[i + 1]);
        return fill(text, values);
    }

    /** Remplace chaque {@code {nom}} par sa valeur. */
    public static String fill(String text, Map<String, String> values) {
        String out = text;
        for (Map.Entry<String, String> entry : values.entrySet()) {
            out = out.replace("{" + entry.getKey() + "}", entry.getValue());
        }
        return out;
    }

    /** La langue dans laquelle Android sert les ressources de cet écran. */
    static String language(Context context) {
        Locale locale = context.getResources().getConfiguration().getLocales().get(0);
        return locale == null ? "en" : locale.getLanguage();
    }

    /**
     * La catégorie CLDR d'un nombre ENTIER. ⚠️ Toute langue ajoutée au pool l'est aussi ici, dans
     * le Swift ({@code category(_:language:)}) et dans les {@code FORMS} de {@code
     * gen-ios-referral-strings.py}.
     */
    public static String category(long count, String language) {
        long n = Math.abs(count);
        long mod10 = n % 10;
        long mod100 = n % 100;
        String base = language.toLowerCase(Locale.ROOT).split("[-_]")[0];
        switch (base) {
            case "ar":
                if (n == 0) return "zero";
                if (n == 1) return "one";
                if (n == 2) return "two";
                if (mod100 >= 3 && mod100 <= 10) return "few";
                if (mod100 >= 11 && mod100 <= 99) return "many";
                return "other";
            case "fr":
            case "pt":
            case "hi":
            case "am":
            case "bn":
            case "fa":
            case "gu":
            case "kn":
            case "si":
                return n == 0 || n == 1 ? "one" : "other";
            case "ru":
            case "uk":
                if (mod10 == 1 && mod100 != 11) return "one";
                if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) return "few";
                return "many";
            case "pl":
                if (n == 1) return "one";
                if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) return "few";
                return "many";
            case "cs":
            case "sk":
                if (n == 1) return "one";
                if (n >= 2 && n <= 4) return "few";
                return "other";
            case "hr":
            case "bs":
            case "sr":
                if (mod10 == 1 && mod100 != 11) return "one";
                if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) return "few";
                return "other";
            case "ro":
                if (n == 1) return "one";
                if (n == 0 || (mod100 >= 2 && mod100 <= 19)) return "few";
                return "other";
            case "he":
            case "iw":
                if (n == 1) return "one";
                if (n == 2) return "two";
                return "other";
            case "lt":
                if (mod100 >= 11 && mod100 <= 19) return "other";
                if (mod10 == 1) return "one";
                if (mod10 >= 2) return "few";
                return "other";
            case "lv":
                if (mod10 == 0 || (mod100 >= 11 && mod100 <= 19)) return "zero";
                if (mod10 == 1 && mod100 != 11) return "one";
                return "other";
            case "sl":
                if (mod100 == 1) return "one";
                if (mod100 == 2) return "two";
                if (mod100 == 3 || mod100 == 4) return "few";
                return "other";
            case "mk":
                return mod10 == 1 && mod100 != 11 ? "one" : "other";
            case "fil":
            case "tl":
                return n <= 3 || (mod10 != 4 && mod10 != 6 && mod10 != 9) ? "one" : "other";
            case "ja":
            case "ko":
            case "zh":
            case "th":
            case "vi":
            case "id":
            case "in":
            case "ms":
            case "km":
            case "lo":
            case "my":
                return "other";
            default:
                return n == 1 ? "one" : "other";
        }
    }
}
