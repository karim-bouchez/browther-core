/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.app.role.RoleManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.AccessState;
import org.chromium.chrome.browser.browther_referral.core.BillingPeriod;
import org.chromium.chrome.browser.browther_referral.core.DefaultBrowserDays;
import org.chromium.chrome.browser.browther_referral.core.ExtraFeature;
import org.chromium.chrome.browser.browther_referral.core.GiftOutcome;
import org.chromium.chrome.browser.browther_referral.core.InvitationItem;
import org.chromium.chrome.browser.browther_referral.core.InvitationStatus;
import org.chromium.chrome.browser.browther_referral.core.MilestoneScale;
import org.chromium.chrome.browser.browther_referral.core.ProgressOutcome;
import org.chromium.chrome.browser.browther_referral.core.RecetteState;
import org.chromium.chrome.browser.browther_referral.core.RedeemOutcome;
import org.chromium.chrome.browser.browther_referral.core.ReferralClient;
import org.chromium.chrome.browser.browther_referral.core.ReferralDate;
import org.chromium.chrome.browser.browther_referral.core.ReferralIdentityBody;
import org.chromium.chrome.browser.browther_referral.core.ReferralLaunch;
import org.chromium.chrome.browser.browther_referral.core.ReferralPlatform;
import org.chromium.chrome.browser.browther_referral.core.ReferralProduct;
import org.chromium.chrome.browser.browther_referral.core.ReferralPrompt;
import org.chromium.chrome.browser.browther_referral.core.ReferralPromptState;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;
import org.chromium.chrome.browser.browther_referral.core.ReferralStorage;
import org.chromium.chrome.browser.browther_referral.core.ShareOutcome;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

/**
 * L'orchestrateur du parrainage Android — docs/PARRAINAGE.md, brief C (§ 10.4) ; port de {@code
 * BrowtherReferralController.swift} (iOS, la référence : private/docs/PARRAINAGE.md § 8.1).
 *
 * <p>Il porte les GESTES (démarrer le mois, partager, saisir un code, le cadeau) et
 * l'ORCHESTRATION (se présenter au service, retenter, relever les jours du filleul, décider d'un
 * écran sur le Nouvel Onglet). Les RÈGLES vivent dans {@code core/} (pur, testé :
 * private/scripts/android-referral-tests) — ⛔ jamais recopiées ici. Les TEXTES dans {@link
 * ReferralStrings}.
 *
 * <h2>Quatre invariants (les mêmes qu'iOS)</h2>
 *
 * <ul>
 *   <li>🔴 Rien ne touche au chemin de navigation : aucune requête ne retient un écran (tout le
 *       réseau part sur un fil à part), toute erreur du service est avalée.
 *   <li>🔴 Sens de la panne : ouvert (§ 7) — dernier statut connu, et sans statut du tout, RIEN
 *       n'est en pause (§ 11.2).
 *   <li>🔴 Trois états, jamais deux : tant que le statut n'est pas connu, ni pause, ni
 *       sollicitation.
 *   <li>🔴 Un aperçu de recette n'écrit RIEN (§ 12.7) : ni état, ni verrou, ni mois démarré, ni
 *       analytique.
 * </ul>
 *
 * <h2>Ce qui change sur Android (§ 8.3)</h2>
 *
 * <ul>
 *   <li>🔴 <b>Le paiement est une PORTE FACTICE</b> (§ 12.27 du doc commun) : Google Play n'ouvre
 *       pas de compte marchand au Maroc. « Je soutiens » offre un mois, une fois ({@link #gift}).
 *       ⛔ Pas de Play Billing « en attendant ».
 *   <li>La preuve du navigateur par défaut est {@code RoleManager.isRoleHeld(ROLE_BROWSER)} : une
 *       lecture directe, sans quota (⛔ pas l'API rationnée d'Apple).
 *   <li>Pas de compte dev&din dans cette version (§ 7.4) : le sujet est l'appareil.
 * </ul>
 *
 * <p>Tout ce qui touche Chromium passe par {@link Platform} ({@code BrowtherReferralChromium}) :
 * l'aperçu à l'émulateur en fournit un faux, sans rien changer ici.
 */
public final class BrowtherReferralController {
    /** Ce que le contrôleur demande au navigateur — ⛔ rien d'autre ne touche Chromium. */
    public interface Platform {
        Context appContext();

        SharedPreferences preferences();

        /** L'analytique PostHog de Browther (projet 171216). */
        void track(String event, Map<String, Object> properties);

        /** Les secondes de musique retirée depuis toujours (statistiques du Nouvel Onglet). */
        long musicSecondsTotal();

        /** Un build du Play Store (officiel) : le flow y suit {@link ReferralLaunch#inStoreBuilds}. */
        boolean isStoreBuild();

        /** L'outil de recette est-il montré ? (build de dev, ou options développeur débloquées) */
        boolean showsRecette();

        boolean isMusicRemovalEnabled();

        void setMusicRemovalEnabled(boolean enabled);

        /** L'activité au premier plan, pour ce qui s'ouvre depuis un toast ou le Nouvel Onglet. */
        @Nullable
        Activity topActivity();
    }

    /** Un écran qui se redessine quand le statut ou l'état local change. */
    public interface Listener {
        void onReferralChanged();
    }

    private static @Nullable Platform sPlatform;
    private static @Nullable BrowtherReferralController sInstance;

    /** Branché une fois au démarrage du navigateur (ou par l'aperçu). */
    public static void install(Platform platform) {
        sPlatform = platform;
    }

    public static BrowtherReferralController get() {
        if (sInstance == null) {
            if (sPlatform == null) sPlatform = BrowtherReferralChromium.platform();
            sInstance = new BrowtherReferralController(sPlatform);
        }
        return sInstance;
    }

    /** Nouvelles tentatives quand le service ne répond pas — puis au retour au premier plan. */
    private static final long[] RETRY_DELAYS_MS = {2_000, 5_000, 15_000, 60_000};

    /** Relire le statut au retour au premier plan, pas plus souvent. */
    private static final long REFRESH_EVERY_MS = 10 * 60 * 1000;

    /** ⭐ Les 3 jours s'annoncent UN PEU APRÈS le partage (§ 12.26). */
    static final long GRACE_TOAST_DELAY_MS = 1_500;

    /** ⭐ Le moment de mérite « après un retrait de musique » (§ 3.1) : une minute aujourd'hui. */
    private static final long MERIT_MUSIC_SECONDS = 60;

    private static final String KEY_DEVICE = "browther.referral.device-subject";
    private static final String KEY_LAST_SOLICITATION = "browther.referral.last-solicitation";

    private final Platform mPlatform;
    private final ReferralStorage mStorage;
    private final Handler mMain = new Handler(Looper.getMainLooper());
    private final ExecutorService mIo = Executors.newSingleThreadExecutor();
    private final List<Listener> mListeners = new ArrayList<>();

    private final boolean mEnabled;
    private @Nullable ReferralStatus mStatus;
    /** ⭐ Un statut FRAIS de cette session — l'OUVERTURE d'un écran l'exige ; le cache suffit pour peindre. */
    private boolean mFresh;
    private ReferralPromptState mPrompt;
    private @Nullable String mSubjectRef;
    private @Nullable ReferralClient mClient;
    /**
     * L'intention de la jauge « jouet » : la réponse à « combien penses-tu pouvoir inviter ? »
     * survit d'un écran à l'autre du MÊME moment (§ 12.20).
     */
    private @Nullable Integer mGaugeIntention;
    /** La formule choisie : ⭐ l'annuel par défaut (§ 3, écran 7). */
    private BillingPeriod mPeriod = BillingPeriod.YEARLY;

    private boolean mBooted;
    private boolean mRegistered;
    private @Nullable ReferralClient mRegistering;
    private int mRetryAttempt;
    private long mLastRefresh;
    private @Nullable String mTrialCatchUpFor;
    private boolean mReporting;
    private @Nullable String mDefaultCheckDay;

    /** Pages réellement chargées aujourd'hui — le « N-ième onglet du jour ». */
    private String mPagesDay = "";
    private int mPagesCount;
    /** Le total de musique retirée au premier passage du jour. */
    private String mMusicDay = "";
    private long mMusicAtDayStart;

    /** 🧪 Faire comme si Sawtunaa était finalisé (en mémoire, le temps d'un lancement). */
    private boolean mRecetteExtrasReleased;

    private BrowtherReferralController(Platform platform) {
        mPlatform = platform;
        SharedPreferences prefs = platform.preferences();
        mStorage =
                new ReferralStorage(
                        new ReferralStorage.Backend() {
                            @Override
                            public @Nullable String get(String key) {
                                return prefs.getString(key, null);
                            }

                            @Override
                            public void put(String key, @Nullable String value) {
                                if (value == null) {
                                    prefs.edit().remove(key).apply();
                                } else {
                                    prefs.edit().putString(key, value).apply();
                                }
                            }
                        });
        mEnabled = ReferralLaunch.isEnabled(platform.isStoreBuild());
        mPrompt = mStorage.prompt();
    }

    // -------------------- Ce que les écrans lisent --------------------

    public void addListener(Listener listener) {
        if (!mListeners.contains(listener)) mListeners.add(listener);
    }

    public void removeListener(Listener listener) {
        mListeners.remove(listener);
    }

    private void notifyChanged() {
        for (Listener listener : new ArrayList<>(mListeners)) listener.onReferralChanged();
    }

    public Context appContext() {
        return mPlatform.appContext();
    }

    public boolean isEnabled() {
        return mEnabled;
    }

    public boolean isFresh() {
        return mFresh;
    }

    public boolean showsRecette() {
        return mPlatform.showsRecette();
    }

    /** Le statut connu (le dernier, ou le cache) — {@code null} tant que rien n'est connu. */
    public @Nullable ReferralStatus known() {
        return mStatus;
    }

    public AccessState access() {
        if (!mEnabled || mSubjectRef == null) return AccessState.unknown;
        return new AccessState(mStatus);
    }

    public MilestoneScale scale() {
        return new MilestoneScale(mStatus);
    }

    public ReferralPromptState prompt() {
        return mPrompt;
    }

    public @Nullable Integer gaugeIntention() {
        return mGaugeIntention;
    }

    public void setGaugeIntention(@Nullable Integer value) {
        mGaugeIntention = value;
        notifyChanged();
    }

    public BillingPeriod period() {
        return mPeriod;
    }

    public void setPeriod(BillingPeriod period) {
        mPeriod = period;
        notifyChanged();
    }

    public boolean isGaugeUnderstood() {
        return mStorage.gaugeUnderstood();
    }

    public void setGaugeUnderstood() {
        mStorage.setGaugeUnderstood(true);
    }

    public boolean isPaused() {
        return mEnabled && extrasReleased() && access().isPaused(Instant.now());
    }

    /**
     * ⭐ Tant que Sawtunaa n'est pas finalisé, RIEN n'est en pause et rien ne sollicite (§ 9) — ni
     * rappel, ni J0, ni garde, ni circuit. ⚠️ Même si le service dit le contraire. Seules les
     * bonnes nouvelles (8, 8 bis) passent.
     */
    public boolean extrasReleased() {
        return ReferralLaunch.extrasReleased || mRecetteExtrasReleased;
    }

    /**
     * ⭐ Une bonne nouvelle attend d'être vue (8 ou 8 bis) : c'est la pastille de la ligne des
     * Paramètres. ⛔ Ni le J−3 ni le J0 : ce sont des sollicitations.
     */
    public boolean hasFreshNews() {
        Pending pending = pending(Instant.now(), null);
        return pending != null && pending.kind == Pending.Kind.NOTICE;
    }

    /**
     * La ligne du rappel posé dans le panneau de la fonctionnalité supplémentaire — {@code null}
     * quand il n'y a rien à dire : avant l'annonce (tout est ouvert, § 12.11), à vie, abonné, ou
     * en pause (le panneau le dit alors avec SES surfaces, § 2.14 : ⛔ pas deux fois).
     */
    public @Nullable String extraCalloutLine(Context context) {
        if (!mEnabled || !extrasReleased() || mStatus == null) return null;
        AccessState access = access();
        if (access.lifetime || mStatus.subscription.active) return null;
        if (isPaused()) return null;
        Instant end = ReferralDate.parse(mStatus.reminder.nextCoverageEnd);
        if (end == null) return ReferralStrings.get(context, "panel.covered");
        return ReferralStrings.fill(
                ReferralStrings.get(context, "panel.coveredUntil"),
                "date",
                ReferralFormat.date(context, end, false));
    }

    /**
     * « Payer » est proposé : ⭐ toujours sur Android — c'est la porte factice (§ 12.27), le
     * parcours du vrai paiement jusqu'au toucher de « Je soutiens ».
     */
    public boolean billingAvailable() {
        return true;
    }

    // -------------------- Le démarrage --------------------

    /** Une fois par lancement — idempotent. */
    public void boot() {
        if (mBooted) return;
        mBooted = true;
        if (!mEnabled) return;
        String device = mStorage.recetteSubject();
        if (device == null) device = deviceSubject();
        useSubject(device);
        register();
    }

    /**
     * L'identité de l'appareil : un UUID gardé dans les préférences de l'app. ⚠️ Pas de trousseau
     * synchronisé sur Android : elle ne survit pas à une désinstallation (le compte dev&din, quand
     * il viendra, fera suivre la personne). ⚠️ Ce n'est PAS l'identifiant de l'analytique.
     */
    private String deviceSubject() {
        SharedPreferences prefs = mPlatform.preferences();
        String existing = prefs.getString(KEY_DEVICE, null);
        if (existing != null && !existing.isEmpty()) return existing;
        String created = UUID.randomUUID().toString().toLowerCase(java.util.Locale.ROOT);
        prefs.edit().putString(KEY_DEVICE, created).apply();
        return created;
    }

    private void useSubject(String subject) {
        mSubjectRef = subject;
        mClient =
                new ReferralClient(
                        new ReferralIdentityBody(
                                ReferralProduct.key, subject, null, ReferralPlatform.ANDROID));
        mStatus = mStorage.cachedStatus(subject);
        mFresh = false;
        mRegistered = false;
        mRetryAttempt = 0;
        mTrialCatchUpFor = null;
        notifyChanged();
    }

    /** Un appel au service sur le fil réseau, son issue sur le fil principal. */
    private <T> void async(Callable<T> call, Consumer<T> onSuccess, @Nullable Runnable onFailure) {
        mIo.execute(
                () -> {
                    try {
                        T value = call.call();
                        mMain.post(() -> onSuccess.accept(value));
                    } catch (Exception e) {
                        if (onFailure != null) mMain.post(onFailure);
                    }
                });
    }

    private void register() {
        ReferralClient client = mClient;
        if (client == null || mRegistering == client) return;
        mRegistering = client;
        async(
                client::register,
                next -> {
                    if (mRegistering == client) mRegistering = null;
                    // Le sujet a changé entre-temps (recette) : ce statut n'est plus le sien.
                    if (mClient != client) return;
                    adopt(next);
                    mRegistered = true;
                    mRetryAttempt = 0;
                    mLastRefresh = System.currentTimeMillis();
                    afterFreshStatus();
                },
                () -> {
                    if (mRegistering == client) mRegistering = null;
                    // 🔴 Sens de la panne : on garde ce qu'on sait, et on retente — puis au retour
                    // au premier plan. ⛔ Jamais une boucle.
                    if (mClient != client || mRetryAttempt >= RETRY_DELAYS_MS.length) return;
                    long delay = RETRY_DELAYS_MS[mRetryAttempt++];
                    mMain.postDelayed(this::register, delay);
                });
    }

    /** Relire le statut (retour d'un geste, écran Parrainage). */
    public void refresh() {
        ReferralClient client = mClient;
        if (client == null) return;
        async(
                client::status,
                next -> {
                    if (mClient != client) return;
                    adopt(next);
                    mLastRefresh = System.currentTimeMillis();
                    afterFreshStatus();
                },
                null);
    }

    /** Retour au premier plan (reprise de l'activité principale). */
    public void onForeground() {
        boot();
        if (!mEnabled || mClient == null) return;
        if (!mRegistered) {
            mRetryAttempt = 0;
            register();
            return;
        }
        if (System.currentTimeMillis() - mLastRefresh < REFRESH_EVERY_MS) return;
        refresh();
    }

    private void adopt(ReferralStatus next) {
        if (mSubjectRef == null) return;
        mStatus = next;
        mFresh = true;
        mStorage.saveStatus(next, mSubjectRef);
        notifyChanged();
    }

    private interface PromptChange {
        ReferralPromptState apply(ReferralPromptState state);
    }

    private void updatePrompt(PromptChange change) {
        ReferralPromptState next = change.apply(mPrompt);
        if (next.equals(mPrompt)) return;
        mPrompt = next;
        mStorage.setPrompt(next);
        notifyChanged();
    }

    /** Ce qui suit chaque statut FRAIS : rattrapages, filleul, photo du jour. */
    private void afterFreshStatus() {
        ReferralStatus status = mStatus;
        ReferralClient client = mClient;
        String subject = mSubjectRef;
        if (status == null || client == null || subject == null) return;

        // ⭐ Une annonce par INSTALLATION (§ 12.11) : une identité qui arrive APRÈS l'annonce
        // (recette) n'aurait jamais son mois.
        if (Boolean.TRUE.equals(mPrompt.announced)
                && status.trial.startedAt == null
                && !subject.equals(mTrialCatchUpFor)) {
            mTrialCatchUpFor = subject;
            async(client::startTrial, this::adopt, () -> mTrialCatchUpFor = null);
        }
        // Le mois a démarré ailleurs : l'annonce « offert 1 mois » ne serait plus vraie.
        // ⚠️ Pas avant le lancement : l'annonce doit rester à montrer ce jour-là.
        if (extrasReleased() && ReferralPrompt.announceAlreadyStarted(mPrompt, status)) {
            updatePrompt(ReferralPrompt::markAnnounced);
        }
        // Aligner ce qui n'a rien à annoncer — ⛔ jamais une validation pas encore montrée.
        updatePrompt(
                state -> {
                    ReferralPromptState next = state;
                    if (state.seenValidated == null) {
                        next = ReferralPrompt.markValidatedSeen(next, status.milestones.validated);
                    }
                    if (!ReferralPrompt.refereeJustValidated(state, status.referredBy)) {
                        next = ReferralPrompt.markRefereeSeen(next, status.referredBy);
                    }
                    return next;
                });
        reportRefereeDays();
        sendDailySnapshot();
    }

    // -------------------- L'usage (§ 3.1, § 9) --------------------

    /**
     * Une vraie page web vient de finir de charger dans un onglet normal ({@code http(s)}, hors
     * navigation privée) — appelé par la barre d'outils à chaque fin de chargement.
     */
    public void notePageLoaded() {
        boot();
        Instant now = Instant.now();
        String today = ReferralDate.localDayKey(now);
        if (today.equals(mPagesDay)) {
            mPagesCount++;
        } else {
            mPagesDay = today;
            mPagesCount = 1;
        }
        noteMusicDayStart(today);
        if (!mEnabled) return;
        updatePrompt(state -> ReferralPrompt.recordBrowsingDay(state, now));
        DefaultBrowserDays days = mStorage.defaultBrowserDays();
        if (days.browsingDays.contains(today) && days.hasProof(now)) return;
        days.recordBrowsing(now);
        // ⭐ La preuve du défaut, une fois par jour : Android la donne directement, sans quota.
        if (!days.hasProof(now) && !today.equals(mDefaultCheckDay)) {
            mDefaultCheckDay = today;
            if (isDefaultBrowser()) days.recordProof(now);
        }
        mStorage.setDefaultBrowserDays(days);
        reportRefereeDays();
    }

    /** Browther est-il le navigateur par défaut ? — le rôle {@code ROLE_BROWSER} du système. */
    public boolean isDefaultBrowser() {
        try {
            RoleManager roles = mPlatform.appContext().getSystemService(RoleManager.class);
            return roles != null
                    && roles.isRoleAvailable(RoleManager.ROLE_BROWSER)
                    && roles.isRoleHeld(RoleManager.ROLE_BROWSER);
        } catch (RuntimeException e) {
            return false;
        }
    }

    /**
     * ⭐ Le FILLEUL déclare ses jours « par défaut » au service (§ 5.2, § 9) — seulement ceux qui
     * SUIVENT la saisie du code, un par jour, jamais deux fois. ⛔ Rien pour qui n'a pas de parrain.
     */
    private void reportRefereeDays() {
        ReferralClient client = mClient;
        ReferralStatus status = mStatus;
        if (client == null || mReporting || status == null || status.referredBy == null) return;
        if (status.referredBy.status != ReferralStatus.ReferredBy.Status.INSTALLED) return;
        List<String> todo =
                mStorage.defaultBrowserDays()
                        .daysToReport(
                                ReferralDate.parse(status.referredBy.redeemedAt),
                                ReferralProduct.validationTargetDays + 2,
                                java.time.ZoneId.systemDefault());
        if (todo.isEmpty()) return;
        mReporting = true;
        async(
                () -> {
                    for (String day : todo) {
                        Instant occurredAt = DefaultBrowserDays.occurredAt(day);
                        if (occurredAt == null) continue;
                        ProgressOutcome outcome =
                                client.reportProgress(
                                        ReferralProduct.validationEvent, "default:" + day, occurredAt);
                        mMain.post(
                                () -> {
                                    DefaultBrowserDays days = mStorage.defaultBrowserDays();
                                    days.markReported(day);
                                    mStorage.setDefaultBrowserDays(days);
                                });
                        if (outcome.progress != null && outcome.progress.validated) break;
                    }
                    return Boolean.TRUE;
                },
                done -> {
                    mReporting = false;
                    refresh();
                },
                // Rattrapé au prochain passage.
                () -> mReporting = false);
    }

    private void noteMusicDayStart(String today) {
        if (today.equals(mMusicDay)) return;
        mMusicDay = today;
        mMusicAtDayStart = mPlatform.musicSecondsTotal();
    }

    /** Le moment de mérite de Browther (§ 3.1) : la N-ième vraie page du jour, ou un retrait de musique aujourd'hui. */
    public boolean isMeritMoment(Instant now) {
        String today = ReferralDate.localDayKey(now);
        noteMusicDayStart(today);
        int pages = today.equals(mPagesDay) ? mPagesCount : 0;
        long music = mPlatform.musicSecondsTotal() - mMusicAtDayStart;
        return pages >= ReferralPrompt.meritPagesPerDay || music >= MERIT_MUSIC_SECONDS;
    }

    // -------------------- Les sollicitations (§ 3) --------------------

    /** Ce que le Nouvel Onglet doit montrer, s'il doit montrer quelque chose. */
    public static final class Pending {
        public enum Kind {
            /** Une bonne nouvelle (8, 8 bis) — ⛔ pas une sollicitation. */
            NOTICE,
            /** 🔴 Le circuit fermé rouvre tant qu'il n'a pas eu sa réponse (§ 12.16). */
            CIRCUIT,
            DECISION
        }

        public final Kind kind;
        public final ReferralScreen screen;
        public final @Nullable ReferralPrompt.Solicitation decision;

        Pending(Kind kind, ReferralScreen screen, @Nullable ReferralPrompt.Solicitation decision) {
            this.kind = kind;
            this.screen = screen;
            this.decision = decision;
        }
    }

    public @Nullable Pending pending(Instant now, @Nullable Boolean merit) {
        ReferralStatus known = mStatus;
        if (!mEnabled || known == null || !mFresh) return null;
        AccessState access = new AccessState(known);
        if (ReferralPrompt.newlyValidated(mPrompt, known.milestones.validated)) {
            return new Pending(Pending.Kind.NOTICE, validatedScreen(known), null);
        }
        if (ReferralPrompt.refereeJustValidated(mPrompt, known.referredBy)) {
            return new Pending(Pending.Kind.NOTICE, ReferralScreen.refereeDone(), null);
        }
        if (!extrasReleased()) return null;
        ReferralPromptState.Circuit entry =
                ReferralPrompt.circuitToRestore(mPrompt, known, access, now);
        if (entry != null) {
            return new Pending(
                    Pending.Kind.CIRCUIT,
                    entry == ReferralPromptState.Circuit.PAUSED
                            ? ReferralScreen.paused(false)
                            : ReferralScreen.support(true),
                    null);
        }
        ReferralPrompt.Solicitation decision =
                ReferralPrompt.decide(
                        new ReferralPrompt.Input(
                                mPrompt,
                                known,
                                access,
                                merit != null ? merit : isMeritMoment(now),
                                extrasReleased(),
                                now));
        if (decision == null) return null;
        return new Pending(Pending.Kind.DECISION, ReferralScreen.of(decision), decision);
    }

    private static ReferralScreen validatedScreen(ReferralStatus status) {
        InvitationItem latest = null;
        for (InvitationItem item : status.invitations.items) {
            if (item.status != InvitationStatus.VALIDATED) continue;
            String at = item.validatedAt == null ? "" : item.validatedAt;
            String best = latest == null || latest.validatedAt == null ? "" : latest.validatedAt;
            if (latest == null || at.compareTo(best) >= 0) latest = item;
        }
        return ReferralScreen.validated(
                Math.max(1, latest == null ? 1 : latest.creditedMonths),
                status.access.until,
                status.access.lifetime);
    }

    /**
     * ⛔ Jamais deux sollicitations le même jour (§ 3.4). Android n'a pas encore d'autres fiches
     * (avis, note) : le verrou est celui du parrainage seul, gardé au même format que l'iOS.
     */
    public boolean canSolicitToday(Instant now) {
        String last = mPlatform.preferences().getString(KEY_LAST_SOLICITATION, null);
        if (last == null) return true;
        Instant at = ReferralDate.parse(last);
        return at == null || !ReferralDate.localDayKey(at).equals(ReferralDate.localDayKey(now));
    }

    private void markSolicitationShown(Instant now) {
        mPlatform.preferences()
                .edit()
                .putString(KEY_LAST_SOLICITATION, ReferralDate.string(now))
                .apply();
    }

    /** 🧪 Ce qu'une tentative a donné — l'outil de recette doit DIRE pourquoi rien ne s'est ouvert (§ 12.18). */
    public enum Attempt {
        SHOWN,
        NONE,
        LOCKED_TODAY,
        BUSY,
        UNKNOWN
    }

    /**
     * ⭐ Une seule fonction décide et ouvre — le Nouvel Onglet l'appelle au bout de son délai,
     * l'outil de recette sans attendre.
     */
    public Attempt attemptSolicitation(
            @Nullable Activity activity, Instant now, @Nullable Boolean merit) {
        if (!mEnabled || mStatus == null || !mFresh) return Attempt.UNKNOWN;
        if (activity == null || !activity.hasWindowFocus()) return Attempt.BUSY;
        Pending pending = pending(now, merit);
        if (pending == null) return Attempt.NONE;
        ReferralStatus known = mStatus;
        switch (pending.kind) {
            case NOTICE:
                if (pending.screen.kind == ReferralScreen.Kind.VALIDATED) {
                    updatePrompt(
                            state ->
                                    ReferralPrompt.markCircuitClosed(
                                            ReferralPrompt.markValidatedSeen(
                                                    state, known.milestones.validated)));
                    Map<String, Object> props = new HashMap<>();
                    props.put("validated", known.milestones.validated);
                    track("referral_validated", props);
                } else {
                    updatePrompt(state -> ReferralPrompt.markRefereeSeen(state, known.referredBy));
                }
                BrowtherReferralPresenter.present(
                        activity, pending.screen, BrowtherReferralPresenter.Source.NOTICE, false);
                return Attempt.SHOWN;
            case CIRCUIT:
                // ⚠️ Pas une nouvelle sollicitation (ni cadence J0) — mais bien un AFFICHAGE.
                BrowtherReferralPresenter.present(
                        activity, pending.screen, BrowtherReferralPresenter.Source.CIRCUIT, false);
                return Attempt.SHOWN;
            case DECISION:
            default:
                if (!canSolicitToday(now)) return Attempt.LOCKED_TODAY;
                markSolicitationShown(now);
                remember(pending.decision, now);
                BrowtherReferralPresenter.present(
                        activity, pending.screen, BrowtherReferralPresenter.Source.PROMPT, false);
                if (pending.decision.kind == ReferralPrompt.Solicitation.Kind.ANNOUNCE) {
                    startTrialNow();
                }
                return Attempt.SHOWN;
        }
    }

    /** Ce que l'affichage écrit — ⛔ jamais avant d'avoir réellement ouvert l'écran. */
    private void remember(ReferralPrompt.Solicitation decision, Instant now) {
        AccessState access = access();
        Instant coverageEnd =
                mStatus == null ? null : ReferralDate.parse(mStatus.reminder.nextCoverageEnd);
        updatePrompt(
                state -> {
                    switch (decision.kind) {
                        case ANNOUNCE:
                            return ReferralPrompt.markAnnounced(state);
                        case PAUSED:
                            ReferralPromptState merited = ReferralPrompt.markMeritUsed(state, now);
                            // ⭐ J0 ouvre le circuit : il survivra au lancement suivant (§ 12.16).
                            return ReferralPrompt.markCircuitOpen(
                                    ReferralPrompt.markPausedShown(
                                            merited,
                                            coverageEnd != null ? coverageEnd : access.until,
                                            now),
                                    ReferralPromptState.Circuit.PAUSED);
                        case ENDING:
                        case REMINDER:
                        default:
                            return ReferralPrompt.markReminderShown(
                                    ReferralPrompt.markMeritUsed(state, now),
                                    access.until,
                                    decision.stage);
                    }
                });
    }

    /** ⭐ Le mois démarre à l'affichage de l'annonce (§ 4), ⛔ pas à l'installation. */
    private void startTrialNow() {
        ReferralClient client = mClient;
        if (client == null) return;
        async(client::startTrial, this::adopt, null);
    }

    // -------------------- Les gestes --------------------

    /** L'écran O a été vu dans l'INTRODUCTION : ⛔ il ne reviendra jamais. */
    public void markWelcomeSeen() {
        updatePrompt(ReferralPrompt::markWelcomed);
    }

    /**
     * « Me le rappeler plus tard » sur l'annonce : un TOAST dit ce que « plus tard » veut dire (0
     * bis, § 12.9) — ⛔ pas un « tu es sûr ? ». Il reste jusqu'à ce qu'on le ferme (§ 12.26).
     */
    public void announceLaterToast(@Nullable Activity activity) {
        if (activity == null) return;
        Instant until = access().until;
        String body =
                until == null
                        ? ReferralStrings.get(activity, "announceLater.bodyNoDate")
                        : ReferralStrings.fill(
                                ReferralStrings.get(activity, "announceLater.body"),
                                "date",
                                ReferralFormat.date(activity, until, false));
        ReferralToast.show(
                activity,
                ReferralStrings.get(activity, "announceLater.title"),
                body + " " + ReferralStrings.get(activity, "announceLater.where"),
                null,
                null,
                true);
    }

    /**
     * Un partage a ABOUTI (destinataire choisi, ou message copié). ⛔ Ne crée aucune invitation :
     * il ne sert qu'au moment « partage » des 3 jours (§ 4), dits APRÈS coup, dans un toast, et
     * seulement s'ils ont été offerts. ⭐ Inviter EST une des trois sorties du circuit.
     */
    public void shareDone(String fromScreen, boolean preview) {
        closeCircuit(preview);
        ReferralClient client = mClient;
        if (client == null) return;
        async(
                client::share,
                (ShareOutcome outcome) -> {
                    if (outcome.grace == null || !outcome.grace.granted) return;
                    if (!preview) {
                        Map<String, Object> props = new HashMap<>();
                        props.put("moment", "share");
                        props.put("screen", fromScreen);
                        track("referral_grace", props);
                    }
                    Instant until = ReferralDate.parse(outcome.grace.coveredUntil);
                    mMain.postDelayed(
                            () -> {
                                Activity activity = mPlatform.topActivity();
                                if (activity == null) return;
                                String body = ReferralStrings.get(activity, "grace.body");
                                if (until != null) {
                                    body += " "
                                            + ReferralStrings.fill(
                                                    ReferralStrings.get(activity, "grace.status"),
                                                    "date",
                                                    ReferralFormat.date(activity, until, false));
                                }
                                ReferralToast.show(
                                        activity,
                                        ReferralStrings.get(activity, "grace.title"),
                                        body,
                                        null,
                                        null,
                                        true);
                            },
                            GRACE_TOAST_DELAY_MS);
                    refresh();
                },
                null);
    }

    /** Le code d'un proche, saisi à la main. {@code null} au rappel = service injoignable. */
    public void redeem(String code, String source, Consumer<RedeemOutcome> onResult) {
        boot();
        ReferralClient client = mClient;
        if (client == null) {
            onResult.accept(null);
            return;
        }
        async(
                () -> client.redeem(code),
                outcome -> {
                    if (outcome.accepted) {
                        Map<String, Object> props = new HashMap<>();
                        props.put("source", source);
                        track("referral_redeemed", props);
                        refresh();
                    }
                    onResult.accept(outcome);
                },
                () -> onResult.accept(null));
    }

    /** 🔴 Une des trois sorties a été prise : le circuit ne rouvrira plus (§ 12.16). */
    public void closeCircuit(boolean preview) {
        if (preview) return;
        updatePrompt(ReferralPrompt::markCircuitClosed);
    }

    /** L'issue de la porte factice : {@code null} = service injoignable. */
    public interface GiftCallback {
        void onGift(@Nullable GiftOutcome outcome);
    }

    /**
     * 🔴 <b>La porte factice du paiement</b> (§ 12.27) : « Je soutiens · … » offre <b>1 mois, UNE
     * fois par sujet</b>, quelle que soit la formule. ⛔ Aucune fausse page de carte : la vérité se
     * dit AU toucher du bouton. Payer étant une des trois sorties du circuit, le cadeau le ferme.
     * ⚠️ Ce n'est pas un paiement : la personne redevient sollicitable à la fin de son mois.
     */
    public void gift(BillingPeriod period, boolean preview, GiftCallback callback) {
        Map<String, Object> started = new HashMap<>();
        started.put("period", period.rawValue);
        if (!preview) track("billing_checkout_started", started);
        ReferralClient client = mClient;
        if (client == null || preview) {
            // ⛔ Un aperçu n'écrit rien : il montre l'écran « cadeau » sans rien demander.
            callback.onGift(preview ? new GiftOutcome(true, access().until == null ? null
                    : ReferralDate.string(access().until)) : null);
            return;
        }
        async(
                () -> client.gift(),
                outcome -> {
                    Map<String, Object> props = new HashMap<>();
                    props.put("period", period.rawValue);
                    props.put("granted", outcome.granted);
                    track("billing_gift", props);
                    closeCircuit(false);
                    refresh();
                    callback.onGift(outcome);
                },
                () -> {
                    Map<String, Object> props = new HashMap<>();
                    props.put("period", period.rawValue);
                    props.put("reason", "error");
                    track("billing_checkout_failed", props);
                    callback.onGift(null);
                });
    }

    /**
     * ⭐ La garde — {@code false} ⇒ un toast dit que c'est en pause, avec « Soutenir dev&din » qui
     * ouvre les trois façons. ⛔ On ne masque JAMAIS le bouton : on l'affiche, et la garde convertit.
     * Hors parrainage, statut inconnu, avant l'annonce : {@code true}. ⛔ Basarunaa n'a pas de garde.
     */
    public boolean requireExtra(ExtraFeature feature, @Nullable Activity activity) {
        if (!isPaused()) return true;
        if (activity != null) {
            ReferralToast.show(
                    activity,
                    ReferralStrings.get(activity, "locked.musicRemoval"),
                    ReferralStrings.get(activity, "locked.body"),
                    ReferralStrings.get(activity, "locked.cta"),
                    () -> {
                        Map<String, Object> props = new HashMap<>();
                        props.put("screen", "locked");
                        props.put("action", "support");
                        track("paywall_action", props);
                        Activity host = mPlatform.topActivity();
                        // Ouverte par la personne elle-même : une fenêtre ORDINAIRE (§ 12.16).
                        BrowtherReferralPresenter.present(
                                host != null ? host : activity,
                                ReferralScreen.support(false),
                                BrowtherReferralPresenter.Source.LOCKED,
                                false);
                    },
                    false);
        }
        Map<String, Object> extra = new HashMap<>();
        extra.put("feature", feature.rawValue);
        BrowtherReferralPresenter.countShown(
                "locked", BrowtherReferralPresenter.Source.LOCKED, false, extra);
        return false;
    }

    /**
     * La pause, pour de vrai (⛔ « blocage seulement affiché », § 11.2) : le retrait de la musique
     * ALLUMÉ quand la couverture tombe s'éteint au Nouvel Onglet suivant — ⚠️ pas au milieu d'une
     * vidéo —, avec le toast de la garde. Dormant tant que Sawtunaa n'est pas finalisé.
     */
    public void enforcePauseIfNeeded(@Nullable Activity activity) {
        if (!isPaused() || !mPlatform.isMusicRemovalEnabled()) return;
        mPlatform.setMusicRemovalEnabled(false);
        Map<String, Object> props = new HashMap<>();
        props.put("feature", ExtraFeature.MUSIC_REMOVAL.rawValue);
        track("feature_paused", props);
        requireExtra(ExtraFeature.MUSIC_REMOVAL, activity);
    }

    // -------------------- La photo du jour (analytique) --------------------

    /**
     * Une par appareil et par jour : couverture, source, jours restants, validées, en cours, clics,
     * filleul, abonnement — ⛔ ni code, ni lien, ni date.
     */
    private void sendDailySnapshot() {
        ReferralStatus known = mStatus;
        if (known == null) return;
        Instant now = Instant.now();
        String today = ReferralDate.localDayKey(now);
        if (today.equals(mStorage.snapshotDay())) return;
        mStorage.setSnapshotDay(today);
        AccessState access = new AccessState(known);
        Map<String, Object> props = new HashMap<>();
        props.put("source", access.source.rawValue);
        props.put("paused", access.isPaused(now));
        props.put("before_trial", access.beforeTrial);
        props.put("lifetime", access.lifetime);
        props.put("validated", known.milestones.validated);
        props.put("in_progress", known.invitations.installed);
        props.put("subscription", known.subscription.active);
        props.put(
                "referee",
                known.referredBy == null ? "none" : known.referredBy.status.rawValue);
        Integer left = access.daysLeft(now);
        if (left != null) props.put("days_left", left);
        if (known.referral.clicks != null) props.put("clicks", known.referral.clicks);
        track("referral_state", props);
    }

    public void track(String event, Map<String, Object> properties) {
        mPlatform.track(event, properties);
    }

    /** Un geste d'écran ({@code paywall_action}, {@code referral_shared}…) — ⛔ muet en aperçu (§ 13.8). */
    public void note(String event, boolean preview, Object... keyValues) {
        if (preview) return;
        // ⛔ Un écran ne se compte jamais lui-même : `paywall_shown` et `referral_state` n'ont
        // qu'une porte chacun (`countShown`, `sendDailySnapshot`).
        if ("paywall_shown".equals(event) || "referral_state".equals(event)) {
            throw new IllegalArgumentException(event + " : réservé à son point unique");
        }
        Map<String, Object> props = new HashMap<>();
        for (int i = 0; i + 1 < keyValues.length; i += 2) {
            props.put(String.valueOf(keyValues[i]), keyValues[i + 1]);
        }
        track(event, props);
    }

    public @Nullable Activity topActivity() {
        return mPlatform.topActivity();
    }

    // -------------------- 🧪 Recette (§ 12.18) --------------------

    public boolean recetteExtrasReleased() {
        return mRecetteExtrasReleased;
    }

    public void setRecetteExtrasReleased(boolean value) {
        mRecetteExtrasReleased = value;
        notifyChanged();
    }

    /** 🧪 Lever le verrou du jour (une sollicitation par jour). */
    public void liftDayLockForRecette() {
        mPlatform.preferences().edit().remove(KEY_LAST_SOLICITATION).apply();
        updatePrompt(
                state -> {
                    ReferralPromptState next = state.copy();
                    next.meritUsedDay = null;
                    return next;
                });
    }

    public @Nullable String recetteToken() {
        return mStorage.recetteToken();
    }

    public void setRecetteToken(@Nullable String token) {
        mStorage.setRecetteToken(token);
    }

    public boolean usesRecetteIdentity() {
        return mStorage.recetteSubject() != null;
    }

    /**
     * Poser une situation COMPLÈTE côté service et remettre l'appareil en cohérence avec elle —
     * sinon un « neuf » qui aurait déjà vu l'annonce ne la reverrait jamais.
     */
    public void applyRecette(String token, RecetteState state, Consumer<Boolean> done) {
        String subject = mSubjectRef;
        if (subject == null) {
            done.accept(false);
            return;
        }
        ReferralClient recetteClient =
                new ReferralClient(
                        new ReferralIdentityBody(
                                ReferralProduct.key, subject, null, ReferralPlatform.ANDROID));
        async(
                () -> recetteClient.applyRecette(token, state),
                next -> {
                    ReferralPromptState fresh = new ReferralPromptState();
                    fresh.welcomed = true;
                    fresh.lastDay = mPrompt.lastDay;
                    fresh.days = mPrompt.days;
                    fresh.announced = state.trialStarted ? Boolean.TRUE : null;
                    fresh = ReferralPrompt.markValidatedSeen(fresh, next.milestones.validated);
                    fresh = ReferralPrompt.markRefereeSeen(fresh, next.referredBy);
                    mPrompt = fresh;
                    mStorage.setPrompt(fresh);
                    adopt(next);
                    mLastRefresh = System.currentTimeMillis();
                    done.accept(true);
                },
                () -> done.accept(false));
    }

    /**
     * 🧪 L'aperçu à l'émulateur (private/scripts/android-intro-preview) : un statut posé tel quel,
     * sans service — ⛔ jamais appelé par le navigateur.
     */
    public void adoptForPreview(ReferralStatus status) {
        // Aucun client : rien ne part vers le service de prod depuis l'émulateur.
        mBooted = true;
        mClient = null;
        mSubjectRef = "preview";
        mStatus = status;
        mFresh = true;
        notifyChanged();
    }

    /** 🧪 Oublier ce que l'appareil a vu (annonce, rappels, circuit). */
    public void forgetPromptForRecette() {
        mPrompt = new ReferralPromptState();
        mStorage.setPrompt(mPrompt);
        notifyChanged();
    }

    /** 🧪 Repartir d'un appareil neuf (une identité de recette par-dessus la vraie), ou revenir à la vraie. */
    public void setRecetteIdentity(boolean fresh) {
        String subject = fresh ? UUID.randomUUID().toString().toLowerCase(java.util.Locale.ROOT) : null;
        mStorage.setRecetteSubject(subject);
        forgetPromptForRecette();
        mStorage.setDefaultBrowserDays(new DefaultBrowserDays());
        // ⭐ Sur Android, pas besoin d'attendre le lancement suivant : le sujet change tout de suite.
        if (mEnabled) {
            useSubject(subject != null ? subject : deviceSubject());
            register();
        }
    }

    /**
     * 🧪 Compter aujourd'hui comme un jour « par défaut » — sans ce geste, la validation du filleul
     * ne se recette pas sur un appareil où Browther n'est pas le navigateur par défaut.
     */
    public void recordDefaultDayForRecette() {
        Instant now = Instant.now();
        DefaultBrowserDays days = mStorage.defaultBrowserDays();
        days.recordProof(now);
        days.recordBrowsing(now);
        mStorage.setDefaultBrowserDays(days);
        reportRefereeDays();
    }

    /** 🧪 Poser le moment de mérite (5 pages aujourd'hui). */
    public void forceMeritForRecette() {
        mPagesDay = ReferralDate.localDayKey(Instant.now());
        mPagesCount = ReferralPrompt.meritPagesPerDay;
    }

    public void resetGaugeUnderstoodForRecette() {
        mStorage.setGaugeUnderstood(false);
    }

    public String debugSummary() {
        Instant now = Instant.now();
        AccessState access = access();
        DefaultBrowserDays days = mStorage.defaultBrowserDays();
        StringBuilder out = new StringBuilder();
        out.append("Parrainage : ").append(mEnabled ? "allumé" : "éteint").append('\n');
        out.append("Sujet : ")
                .append(mSubjectRef == null ? "—" : mSubjectRef.substring(0, 8) + "…")
                .append(usesRecetteIdentity() ? " (recette)" : " (appareil)")
                .append('\n');
        out.append("Statut : ")
                .append(mStatus == null ? "inconnu" : mFresh ? "frais" : "en cache")
                .append('\n');
        ReferralStatus known = mStatus;
        if (known != null) {
            out.append("Code : ").append(known.referral.code).append('\n');
            out.append("Couverture : ")
                    .append(access.source.rawValue)
                    .append(' ')
                    .append(known.access.until == null ? "" : known.access.until)
                    .append(access.beforeTrial ? " (avant l'annonce)" : "")
                    .append('\n');
            out.append("En pause : ").append(access.isPaused(now) ? "oui" : "non").append('\n');
            out.append("Invitations : ")
                    .append(known.milestones.validated)
                    .append(" validées · ")
                    .append(known.invitations.installed)
                    .append(" en cours\n");
            out.append("Filleul : ")
                    .append(
                            known.referredBy == null
                                    ? "non"
                                    : known.referredBy.status.rawValue
                                            + (known.referredBy.progress == null
                                                    ? ""
                                                    : " "
                                                            + (int) known.referredBy.progress.current
                                                            + "/"
                                                            + (int) known.referredBy.progress.target))
                    .append('\n');
            out.append("Rappel : ")
                    .append(
                            known.reminder.reminderCase == null
                                    ? "—"
                                    : known.reminder.reminderCase.rawValue)
                    .append('\n');
        }
        out.append("Annonce vue : ")
                .append(Boolean.TRUE.equals(mPrompt.announced) ? "oui" : "non")
                .append(" · jours de navigation : ")
                .append(mPrompt.days == null ? 0 : mPrompt.days)
                .append('\n');
        out.append("Sawtunaa finalisé : ")
                .append(ReferralLaunch.extrasReleased ? "oui" : "non (pas d'annonce)")
                .append(mRecetteExtrasReleased ? " — recette : oui" : "")
                .append('\n');
        out.append("Navigateur par défaut : ").append(isDefaultBrowser() ? "oui" : "non").append('\n');
        out.append("Mérite maintenant : ")
                .append(isMeritMoment(now) ? "oui" : "non")
                .append(" · jour libre : ")
                .append(canSolicitToday(now) ? "oui" : "non")
                .append('\n');
        out.append("Jours « par défaut » : prouvés ").append(tail(days.proofDays)).append('\n');
        out.append("   navigués ").append(tail(days.browsingDays)).append('\n');
        out.append("   déclarés ").append(tail(days.reportedDays)).append('\n');
        Pending pending = pending(now, null);
        if (pending == null) {
            out.append("Dû : rien");
        } else if (pending.kind == Pending.Kind.NOTICE) {
            out.append("Dû : bonne nouvelle (").append(pending.screen.analyticsName()).append(')');
        } else if (pending.kind == Pending.Kind.CIRCUIT) {
            out.append("Dû : circuit à rouvrir (").append(pending.screen.analyticsName()).append(')');
        } else {
            out.append("Dû : ").append(pending.screen.analyticsName());
        }
        return out.toString();
    }

    private static String tail(List<String> days) {
        int from = Math.max(0, days.size() - 5);
        return String.join(", ", days.subList(from, days.size()));
    }
}
