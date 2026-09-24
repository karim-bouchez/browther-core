/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumSet;
import java.util.List;

/**
 * L'état de l'introduction Browther. Une seule source de vérité pour les six écrans : c'est lui
 * qui décide ce que fait « Continuer » selon l'accès anticipé, qui écrit les préférences, et qui
 * émet l'analytique.
 *
 * <p>Portage Android de {@code BrowtherIntroModel.swift} (iOS, référence recettée) et de {@code
 * model.ts} (desktop). 🔴 Spécification : {@code private/docs/ONBOARDING-SPEC.md} — chaque ⛔ des
 * commentaires de ce dossier y correspond à une version codée, vue à l'écran et refusée.
 *
 * <p>Ne dépend que de Java : tout ce qui touche Chromium (préférences, analytique, rôle de
 * navigateur par défaut) passe par {@link Host}.
 */
public final class BrowtherIntroModel {
    /**
     * Les écrans, dans l'ordre du parcours.
     *
     * <p>⚠️ {@link #key} part à l'analytique : c'est une clé de série, jamais un texte affiché. La
     * renommer casse l'entonnoir du dashboard.
     */
    public enum Step {
        WELCOME("welcome"),
        ADS("ads"),
        BLUR("blur"),
        MUSIC("music"),
        DEFAULT_BROWSER("default"),
        /** O — le code d'un proche (private/docs/PARRAINAGE.md § 1), si le parrainage existe. */
        REFERRAL_CODE("referral_code"),
        CHANNELS("channels");

        public final String key;

        Step(String key) {
            this.key = key;
        }
    }

    /** Les deux fonctionnalités que l'introduction présente et propose d'activer. */
    public enum Feature {
        BASARUNAA("basarunaa"),
        SAWTUNAA("sawtunaa");

        public final String key;

        Feature(String key) {
            this.key = key;
        }
    }

    /** Qui reste flouté. Les valeurs sont celles de {@code brave.basarunaa.mode}. */
    public enum BlurTarget {
        WOMEN("blur-female"),
        MEN("blur-male"),
        BOTH("blur-all");

        public final String mode;

        BlurTarget(String mode) {
            this.mode = mode;
        }
    }

    /**
     * Les deux canaux de diffusion dev&din. Mêmes URL que le bandeau du Nouvel Onglet et les
     * panneaux — {@code grep 0029Vb8ydkv5vKABH78PVX32}.
     */
    public enum Channel {
        WHATSAPP(
                "https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32",
                "marketing_whatsapp_channel_clicked"),
        TELEGRAM("https://t.me/devndin_nouveautes", "marketing_telegram_channel_clicked");

        public final String url;
        public final String event;

        Channel(String url, String event) {
            this.url = url;
            this.event = event;
        }
    }

    /** Les retours haptiques du parcours (ONBOARDING-SPEC.md § 3.5). */
    public enum Haptic {
        /** Changement d'écran. */
        LIGHT,
        /** Bascule d'un interrupteur, « Continuer » pendant l'accès anticipé. */
        MEDIUM,
        /** Choix de qui flouter. */
        SELECTION,
        /** Première activation d'un écran, fin du parcours. */
        SUCCESS
    }

    /** Ce que le modèle demande au navigateur. */
    public interface Host {
        /** Écrit {@code brave.basarunaa.mode}. */
        void writeBasarunaaMode(String mode);

        /** Allume vraiment la fonctionnalité (hors accès anticipé seulement). */
        void enableFeature(Feature feature);

        /**
         * Demande à devenir le navigateur par défaut.
         *
         * @return vrai si une réponse arrivera par {@link #onDefaultBrowserResult} (feuille
         *     système du rôle), faux si rien n'est à attendre (réglages système ouverts).
         */
        boolean requestDefaultBrowser();

        void openUrl(String url);

        /**
         * Émet un évènement. {@code keyValues} alterne clés et valeurs ; les valeurs gardent leur
         * type (booléen, entier, texte), comme sur iOS et desktop.
         */
        void track(String event, Object... keyValues);

        /** Fin du parcours : le navigateur prend la main. */
        void finish();

        /**
         * Le parrainage existe-t-il dans ce binaire ? Alors l'écran O (le code d'un proche) suit
         * « navigateur par défaut ». Faux par défaut : l'aperçu hors Chromium n'a pas à le savoir.
         */
        default boolean referralEnabled() {
            return false;
        }
    }

    /** Ce que l'écran observe. */
    public interface Listener {
        /** L'écran courant a changé ; {@code direction} vaut 1 en avançant, -1 en reculant. */
        void onStepChanged(Step previous, int direction);

        /** Un interrupteur, la cible ou la feuille ont changé. */
        void onStateChanged();

        /** Tir de confettis, par-dessus tout l'écran. */
        void onCelebrate();

        void onHaptic(Haptic haptic);
    }

    private final Host mHost;
    private final boolean mIsEarlyAccess;
    private final List<Step> mSteps;
    private final List<Listener> mListeners = new ArrayList<>();

    private int mIndex;
    private boolean mAdsDemoOn;
    private boolean mBlurDemoOn;
    private boolean mMusicDemoOn;

    /**
     * Vrai dès que le floutage a été allumé une fois. Il change ce que montre l'état « éteint » :
     * <b>rideau</b> tant qu'on n'a rien vu, <b>médias d'origine</b> ensuite — la personne a vu le
     * résultat et demande à comparer, c'est son geste.
     */
    private boolean mBlurDemoEverOn;

    /**
     * Le floutage part sur « les femmes » : le cas d'usage majoritaire, et le défaut du moteur —
     * l'introduction n'invente pas un réglage que l'app n'a pas.
     */
    private BlurTarget mBlurTarget = BlurTarget.WOMEN;

    /** Non nul quand la feuille « Ça arrive bientôt » est ouverte. */
    private Feature mSoonFeature;

    /** Une seule gerbe par écran : sinon l'effet devient une récompense qu'on farme. */
    private final EnumSet<Step> mCelebrated = EnumSet.noneOf(Step.class);

    private boolean mWaitingDefaultBrowser;
    private boolean mFinished;

    /**
     * @param isDefaultBrowser l'écran « navigateur par défaut » saute si Browther l'est déjà —
     *     inutile de demander ce qui est fait.
     * @param isEarlyAccess {@code BrowtherEarlyAccess.ENABLED} : vrai = « Continuer » sur
     *     Basarunaa / Sawtunaa ouvre la feuille « Ça arrive bientôt » au lieu d'allumer.
     */
    public BrowtherIntroModel(Host host, boolean isDefaultBrowser, boolean isEarlyAccess) {
        mHost = host;
        mIsEarlyAccess = isEarlyAccess;
        List<Step> steps = new ArrayList<>();
        steps.add(Step.WELCOME);
        steps.add(Step.ADS);
        steps.add(Step.BLUR);
        steps.add(Step.MUSIC);
        if (!isDefaultBrowser) {
            steps.add(Step.DEFAULT_BROWSER);
        }
        // Browther : l'écran O du parrainage, juste après « navigateur par défaut » (comme iOS).
        if (host.referralEnabled()) {
            steps.add(Step.REFERRAL_CODE);
        }
        steps.add(Step.CHANNELS);
        mSteps = Collections.unmodifiableList(steps);
    }

    public void addListener(Listener listener) {
        mListeners.add(listener);
    }

    /** À appeler une fois l'écran monté : émet la vue du premier écran. */
    public void start() {
        trackStep();
    }

    // -------------------- Lecture --------------------

    public List<Step> getSteps() {
        return mSteps;
    }

    public int getIndex() {
        return mIndex;
    }

    public Step getStep() {
        return mSteps.get(mIndex);
    }

    public boolean isEarlyAccess() {
        return mIsEarlyAccess;
    }

    public boolean isAdsDemoOn() {
        return mAdsDemoOn;
    }

    public boolean isBlurDemoOn() {
        return mBlurDemoOn;
    }

    public boolean isBlurDemoEverOn() {
        return mBlurDemoEverOn;
    }

    public boolean isMusicDemoOn() {
        return mMusicDemoOn;
    }

    public BlurTarget getBlurTarget() {
        return mBlurTarget;
    }

    public Feature getSoonFeature() {
        return mSoonFeature;
    }

    // -------------------- Navigation --------------------

    public void advance() {
        if (mIndex + 1 >= mSteps.size()) {
            finish();
            return;
        }
        Step previous = getStep();
        mIndex++;
        haptic(Haptic.LIGHT);
        for (Listener listener : mListeners) listener.onStepChanged(previous, 1);
        trackStep();
    }

    /** @return faux s'il n'y a pas d'écran précédent. */
    public boolean back() {
        if (mIndex == 0) return false;
        Step previous = getStep();
        mIndex--;
        haptic(Haptic.LIGHT);
        for (Listener listener : mListeners) listener.onStepChanged(previous, -1);
        trackStep();
        return true;
    }

    public void finish() {
        if (mFinished) return;
        mFinished = true;
        haptic(Haptic.SUCCESS);
        mHost.track(
                "onboarding_completed",
                "blur_target",
                mBlurTarget.mode,
                "early_access",
                mIsEarlyAccess);
        mHost.finish();
    }

    private void trackStep() {
        mHost.track(
                "onboarding_step_viewed",
                "step",
                getStep().key,
                "index",
                mIndex,
                "early_access",
                mIsEarlyAccess);
    }

    // -------------------- Démonstrations --------------------

    /**
     * L'interrupteur de démonstration. Il ne règle rien : il montre la page avec et sans
     * Browther.
     */
    public void toggleDemo(Step step) {
        boolean on;
        switch (step) {
            case ADS:
                mAdsDemoOn = !mAdsDemoOn;
                on = mAdsDemoOn;
                break;
            case BLUR:
                mBlurDemoOn = !mBlurDemoOn;
                on = mBlurDemoOn;
                if (on) mBlurDemoEverOn = true;
                break;
            case MUSIC:
                mMusicDemoOn = !mMusicDemoOn;
                on = mMusicDemoOn;
                break;
            default:
                return;
        }
        haptic(Haptic.MEDIUM);
        mHost.track("onboarding_demo_toggled", "step", step.key, "on", on);
        notifyState();
        if (on && !mCelebrated.contains(step)) {
            mCelebrated.add(step);
            haptic(Haptic.SUCCESS);
            for (Listener listener : mListeners) listener.onCelebrate();
        }
    }

    public void choose(BlurTarget target) {
        if (target == mBlurTarget) return;
        mBlurTarget = target;
        // Écrit tout de suite, même si le floutage est encore désactivé : la personne retrouvera
        // son choix le jour où il s'allume.
        mHost.writeBasarunaaMode(target.mode);
        haptic(Haptic.SELECTION);
        mHost.track("onboarding_blur_target_chosen", "value", target.mode);
        notifyState();
    }

    // -------------------- Activation --------------------

    /**
     * Pendant l'accès anticipé, « Continuer » explique que la fonctionnalité arrive ; à la sortie,
     * il l'allume vraiment, puis avance. Le même bouton, deux réponses — c'est le seul écart entre
     * les deux états de l'introduction.
     */
    public void activate(Feature feature) {
        mHost.track(
                "onboarding_activate_tapped", "feature", feature.key, "available", !mIsEarlyAccess);
        // ⚠️ Le choix « qui flouter » est écrit MÊME en accès anticipé, et même si la personne n'a
        // touché à aucune case : sinon le choix affiché ne serait pas celui qui s'applique.
        if (feature == Feature.BASARUNAA) {
            mHost.writeBasarunaaMode(mBlurTarget.mode);
        }
        if (mIsEarlyAccess) {
            // Le geste a un effet : la feuille arrive, et on le sent — sinon « Continuer » donne
            // l'impression de n'avoir rien fait.
            haptic(Haptic.MEDIUM);
            mSoonFeature = feature;
            notifyState();
            return;
        }
        haptic(Haptic.SUCCESS);
        mHost.enableFeature(feature);
        mHost.track("feature_toggled", "feature", feature.key, "enabled", true, "source", "onboarding");
        advance();
    }

    /** La feuille « Ça arrive bientôt » se referme ; {@code thenAdvance} = son bouton primaire. */
    public void dismissSoonSheet(boolean thenAdvance) {
        if (mSoonFeature == null) return;
        mSoonFeature = null;
        notifyState();
        if (thenAdvance) advance();
    }

    // -------------------- Navigateur par défaut --------------------

    public void setAsDefaultBrowser() {
        if (mWaitingDefaultBrowser) return;
        haptic(Haptic.SUCCESS);
        mWaitingDefaultBrowser = mHost.requestDefaultBrowser();
        // Sans feuille système à attendre (réglages ouverts), on avance tout de suite : la personne
        // doit retrouver la suite du parcours en revenant, pas l'écran qu'elle a réglé.
        if (!mWaitingDefaultBrowser) advance();
    }

    /** Réponse de la feuille système du rôle « navigateur ». */
    public void onDefaultBrowserResult(boolean isDefault) {
        if (!mWaitingDefaultBrowser) return;
        mWaitingDefaultBrowser = false;
        if (isDefault) {
            mHost.track("default_browser_set", "source", "onboarding");
        }
        if (getStep() == Step.DEFAULT_BROWSER) advance();
    }

    public void later() {
        mHost.track("onboarding_later_tapped", "feature", "default_browser");
        advance();
    }

    /** « Plus tard » sur l'écran O : le code d'un proche reste saisissable dans « Parrainage ». */
    public void referralLater() {
        mHost.track("onboarding_later_tapped", "feature", "referral_code");
        advance();
    }

    /** Un code accepté se fête : confettis (une fois) et haptique de succès. */
    public void celebrateReferralCode() {
        if (mCelebrated.contains(Step.REFERRAL_CODE)) return;
        mCelebrated.add(Step.REFERRAL_CODE);
        haptic(Haptic.SUCCESS);
        for (Listener listener : mListeners) listener.onCelebrate();
    }

    // -------------------- Canaux dev&din --------------------

    public void openChannel(Channel channel) {
        mHost.track(channel.event, "source", "onboarding");
        mHost.openUrl(channel.url);
    }

    // -------------------- Interne --------------------

    private void notifyState() {
        for (Listener listener : mListeners) listener.onStateChanged();
    }

    private void haptic(Haptic haptic) {
        for (Listener listener : mListeners) listener.onHaptic(haptic);
    }
}
