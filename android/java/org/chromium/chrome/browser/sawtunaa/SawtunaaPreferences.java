/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import android.os.Bundle;

import androidx.preference.Preference;

import org.chromium.base.supplier.MonotonicObservableSupplier;
import org.chromium.base.supplier.ObservableSuppliers;
import org.chromium.base.supplier.SettableMonotonicObservableSupplier;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.basarunaa.BasarunaaBenchmark;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.settings.BravePreferenceFragment;
import org.chromium.components.browser_ui.settings.ChromeSwitchPreference;
import org.chromium.components.browser_ui.settings.SettingsUtils;
import org.chromium.components.user_prefs.UserPrefs;

/**
 * Settings fragment for Sawtunaa (music/noise suppression).
 *
 * <p>Sawtunaa Voie B — Jalon 1. UI minimale : un toggle ON/OFF lié à la pref
 * Chromium {@code kSawtunaaEnabled} (exposée en Java via {@link BravePref#SAWTUNAA_ENABLED},
 * auto-générée par {@code java_cpp_strings}), plus un bouton "Run benchmark" qui
 * exécute {@link SawtunaaBenchmark} et affiche le résultat dans le summary du
 * dernier Preference de la liste.
 *
 * <p>Le toggle ON ne déclenche rien pour l'instant — c'est le Jalon 2 qui câblera
 * le {@code SawtunaaTabHelper} (pipeline audio temps réel). Pour le Jalon 1 c'est
 * juste un placeholder qui valide la chaîne pref ↔ UI.
 */
@NullMarked
public class SawtunaaPreferences extends BravePreferenceFragment {

    public static final String PREF_SAWTUNAA_ENABLED = "sawtunaa_enabled";
    public static final String PREF_SAWTUNAA_RUN_BENCHMARK = "sawtunaa_run_benchmark";
    public static final String PREF_SAWTUNAA_BENCHMARK_RESULT = "sawtunaa_benchmark_result";
    public static final String PREF_SAWTUNAA_RUN_FULL_PIPELINE_BENCH =
            "sawtunaa_run_full_pipeline_bench";
    public static final String PREF_SAWTUNAA_FULL_PIPELINE_BENCH_RESULT =
            "sawtunaa_full_pipeline_bench_result";
    // Browther: Basarunaa Jalon 1 — bench ML runtime piggyback sur cette page.
    public static final String PREF_BASARUNAA_RUN_BENCHMARK = "basarunaa_run_benchmark";
    public static final String PREF_BASARUNAA_BENCHMARK_RESULT = "basarunaa_benchmark_result";

    private final SettableMonotonicObservableSupplier<String> mPageTitle =
            ObservableSuppliers.createMonotonic();

    @Nullable private ChromeSwitchPreference mEnabledPref;
    @Nullable private Preference mRunBenchmarkPref;
    @Nullable private Preference mBenchmarkResultPref;
    @Nullable private Preference mRunFullPipelinePref;
    @Nullable private Preference mFullPipelineResultPref;
    @Nullable private Preference mRunBasarunaaBenchPref;
    @Nullable private Preference mBasarunaaBenchResultPref;
    private boolean mBenchRunning;
    private boolean mFullPipelineRunning;
    private boolean mBasarunaaBenchRunning;

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mPageTitle.set(getString(R.string.sawtunaa_title));
        SettingsUtils.addPreferencesFromResource(this, R.xml.sawtunaa_preferences);
    }

    @Override
    public MonotonicObservableSupplier<String> getPageTitle() {
        return mPageTitle;
    }

    @Override
    public void onActivityCreated(@Nullable Bundle savedInstanceState) {
        super.onActivityCreated(savedInstanceState);

        mEnabledPref = (ChromeSwitchPreference) findPreference(PREF_SAWTUNAA_ENABLED);
        if (mEnabledPref != null) {
            final boolean enabled =
                    UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                            .getBoolean(BravePref.SAWTUNAA_ENABLED);
            mEnabledPref.setChecked(enabled);
            mEnabledPref.setOnPreferenceChangeListener(
                    (pref, newValue) -> {
                        UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                                .setBoolean(BravePref.SAWTUNAA_ENABLED, (boolean) newValue);
                        return true;
                    });
        }

        mRunBenchmarkPref = findPreference(PREF_SAWTUNAA_RUN_BENCHMARK);
        mBenchmarkResultPref = findPreference(PREF_SAWTUNAA_BENCHMARK_RESULT);
        if (mRunBenchmarkPref != null) {
            mRunBenchmarkPref.setOnPreferenceClickListener(
                    pref -> {
                        startBenchmark();
                        return true;
                    });
        }

        mRunFullPipelinePref = findPreference(PREF_SAWTUNAA_RUN_FULL_PIPELINE_BENCH);
        mFullPipelineResultPref = findPreference(PREF_SAWTUNAA_FULL_PIPELINE_BENCH_RESULT);
        if (mRunFullPipelinePref != null) {
            mRunFullPipelinePref.setOnPreferenceClickListener(
                    pref -> {
                        startFullPipelineBenchmark();
                        return true;
                    });
        }

        mRunBasarunaaBenchPref = findPreference(PREF_BASARUNAA_RUN_BENCHMARK);
        mBasarunaaBenchResultPref = findPreference(PREF_BASARUNAA_BENCHMARK_RESULT);
        if (mRunBasarunaaBenchPref != null) {
            mRunBasarunaaBenchPref.setOnPreferenceClickListener(
                    pref -> {
                        startBasarunaaBenchmark();
                        return true;
                    });
        }
    }

    private void startBenchmark() {
        if (mBenchRunning) return;
        mBenchRunning = true;
        if (mRunBenchmarkPref != null) {
            mRunBenchmarkPref.setEnabled(false);
        }
        if (mBenchmarkResultPref != null) {
            mBenchmarkResultPref.setSummary(getString(R.string.sawtunaa_benchmark_result_running));
        }
        SawtunaaBenchmark.run(
                (result, error) -> {
                    mBenchRunning = false;
                    if (mRunBenchmarkPref != null) {
                        mRunBenchmarkPref.setEnabled(true);
                    }
                    if (mBenchmarkResultPref == null) return;
                    if (result != null) {
                        mBenchmarkResultPref.setSummary(result.formatted());
                    } else {
                        mBenchmarkResultPref.setSummary(
                                getString(
                                        R.string.sawtunaa_benchmark_result_error,
                                        error == null ? "?" : error));
                    }
                });
    }

    private void startFullPipelineBenchmark() {
        if (mFullPipelineRunning) return;
        mFullPipelineRunning = true;
        if (mRunFullPipelinePref != null) {
            mRunFullPipelinePref.setEnabled(false);
        }
        if (mFullPipelineResultPref != null) {
            mFullPipelineResultPref.setSummary(
                    getString(R.string.sawtunaa_benchmark_result_running));
        }
        SawtunaaBenchmark.runFullPipeline(
                (result, error) -> {
                    mFullPipelineRunning = false;
                    if (mRunFullPipelinePref != null) {
                        mRunFullPipelinePref.setEnabled(true);
                    }
                    if (mFullPipelineResultPref == null) return;
                    if (result != null) {
                        mFullPipelineResultPref.setSummary(result.formatted());
                    } else {
                        mFullPipelineResultPref.setSummary(
                                getString(
                                        R.string.sawtunaa_benchmark_result_error,
                                        error == null ? "?" : error));
                    }
                });
    }

    /**
     * Browther — Basarunaa Jalon 1 : bench séquentiel des 4 modèles ONNX × 2
     * backends (CPU puis NNAPI), agrège les résultats dans le summary du
     * preference. Pas de loc côté résultats — texte ASCII multi-lignes destiné
     * au copier-coller logcat/dashboard.
     */
    private void startBasarunaaBenchmark() {
        if (mBasarunaaBenchRunning) return;
        mBasarunaaBenchRunning = true;
        if (mRunBasarunaaBenchPref != null) {
            mRunBasarunaaBenchPref.setEnabled(false);
        }
        if (mBasarunaaBenchResultPref != null) {
            mBasarunaaBenchResultPref.setSummary(
                    getString(R.string.sawtunaa_benchmark_result_running));
        }

        final BasarunaaBenchmark.Model[] models = BasarunaaBenchmark.Model.values();
        final BasarunaaBenchmark.Backend[] backends = {
            BasarunaaBenchmark.Backend.CPU, BasarunaaBenchmark.Backend.NNAPI
        };
        final StringBuilder report = new StringBuilder();
        runBasarunaaBenchSequence(models, backends, 0, 0, report);
    }

    private void runBasarunaaBenchSequence(
            BasarunaaBenchmark.Model[] models,
            BasarunaaBenchmark.Backend[] backends,
            int modelIdx,
            int backendIdx,
            StringBuilder report) {
        if (modelIdx >= models.length) {
            // Done — display.
            mBasarunaaBenchRunning = false;
            if (mRunBasarunaaBenchPref != null) {
                mRunBasarunaaBenchPref.setEnabled(true);
            }
            if (mBasarunaaBenchResultPref != null) {
                mBasarunaaBenchResultPref.setSummary(report.toString());
            }
            return;
        }
        BasarunaaBenchmark.run(
                models[modelIdx],
                backends[backendIdx],
                (result, error) -> {
                    if (result != null) {
                        report.append(result.formatted()).append('\n');
                    } else {
                        report.append(models[modelIdx].name())
                                .append(" [")
                                .append(backends[backendIdx].name())
                                .append("] FAILED: ")
                                .append(error == null ? "?" : error)
                                .append('\n');
                    }
                    int nextBackend = backendIdx + 1;
                    int nextModel = modelIdx;
                    if (nextBackend >= backends.length) {
                        nextBackend = 0;
                        nextModel = modelIdx + 1;
                    }
                    // Live update du summary pour montrer la progression.
                    if (mBasarunaaBenchResultPref != null) {
                        mBasarunaaBenchResultPref.setSummary(report.toString());
                    }
                    runBasarunaaBenchSequence(
                            models, backends, nextModel, nextBackend, report);
                });
    }
}
