// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/referral/browther_referral_usage.h"

#include <algorithm>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/functional/callback_helpers.h"
#include "base/strings/stringprintf.h"
#include "base/task/thread_pool.h"
#include "brave/browser/browther/referral/browther_referral_prefs.h"
#include "brave/components/browther_analytics/pref_names.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/shell_integration.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"

namespace browther_referral {

namespace {

constexpr char kDay[] = "day";
constexpr char kPages[] = "pages";
constexpr char kMusicBaseline[] = "musicBaseline";
constexpr char kBrowsingDays[] = "browsingDays";
constexpr char kProofDays[] = "proofDays";
constexpr char kLastDefaultCheck[] = "lastDefaultCheck";
constexpr char kIsDefault[] = "isDefault";

// Un filleul valide en quelques jours : un registre qui grandirait sans fin
// n'apprendrait rien de plus (même borne que l'iOS, `DefaultBrowserDays`).
constexpr size_t kKeptDays = 60;
// Tant que le jour n'est pas prouvé, on redemande à l'OS au plus toutes les
// 30 min : quelqu'un qui règle Browther par défaut en cours de journée voit ce
// jour compter, sans une question système à chaque page.
constexpr base::TimeDelta kDefaultRecheck = base::Minutes(30);

int MusicTotal(PrefService* local_state) {
  return local_state->GetInteger(
      browther_analytics::prefs::kStatsMusicSecondsTotal);
}

// Le jour a changé : pages remises à zéro, repère de musique posé sur le cumul
// actuel. ⚠️ La musique retirée avant le PREMIER fait du jour tombe dans le
// repère — sans conséquence : elle suppose une page chargée, qui roule le jour
// avant que le son ne passe.
void RollDay(base::DictValue& usage, PrefService* local_state) {
  const std::string today = LocalDayKey(base::Time::Now());
  const std::string* day = usage.FindString(kDay);
  if (day && *day == today) {
    return;
  }
  usage.Set(kDay, today);
  usage.Set(kPages, 0);
  usage.Set(kMusicBaseline, MusicTotal(local_state));
}

void InsertDay(base::DictValue& usage,
               const char* key,
               const std::string& day) {
  std::vector<std::string> days;
  if (const base::ListValue* list = usage.FindList(key)) {
    for (const auto& value : *list) {
      if (value.is_string()) {
        days.push_back(value.GetString());
      }
    }
  }
  if (std::find(days.begin(), days.end(), day) != days.end()) {
    return;
  }
  days.push_back(day);
  std::sort(days.begin(), days.end());
  if (days.size() > kKeptDays) {
    days.erase(days.begin(), days.end() - kKeptDays);
  }
  base::ListValue out;
  for (const auto& d : days) {
    out.Append(d);
  }
  usage.Set(key, std::move(out));
}

bool HasProofToday(const base::DictValue& usage) {
  const std::string today = LocalDayKey(base::Time::Now());
  if (const base::ListValue* list = usage.FindList(kProofDays)) {
    for (const auto& value : *list) {
      if (value.is_string() && value.GetString() == today) {
        return true;
      }
    }
  }
  return false;
}

void RecordDefaultAnswer(PrefService* local_state, bool is_default) {
  ScopedDictPrefUpdate update(local_state, prefs::kUsage);
  RollDay(update.Get(), local_state);
  update->Set(kIsDefault, is_default);
  update->Set(kLastDefaultCheck,
              base::Time::Now().InMillisecondsFSinceUnixEpoch());
  if (is_default) {
    InsertDay(update.Get(), kProofDays, LocalDayKey(base::Time::Now()));
  }
}

}  // namespace

std::string LocalDayKey(base::Time time) {
  base::Time::Exploded exploded;
  time.LocalExplode(&exploded);
  return base::StringPrintf("%04d-%02d-%02d", exploded.year, exploded.month,
                            exploded.day_of_month);
}

void RecordRealPageLoad(PrefService* local_state) {
  if (!local_state) {
    return;
  }
  bool should_check = false;
  {
    ScopedDictPrefUpdate update(local_state, prefs::kUsage);
    base::DictValue& usage = update.Get();
    RollDay(usage, local_state);
    usage.Set(kPages, usage.FindInt(kPages).value_or(0) + 1);
    InsertDay(usage, kBrowsingDays, LocalDayKey(base::Time::Now()));
    if (!HasProofToday(usage)) {
      const std::optional<double> last = usage.FindDouble(kLastDefaultCheck);
      should_check =
          !last || base::Time::Now() -
                           base::Time::FromMillisecondsSinceUnixEpoch(*last) >=
                       kDefaultRecheck;
    }
  }
  if (should_check) {
    CheckDefaultBrowser(local_state, base::DoNothing());
  }
}

void CheckDefaultBrowser(PrefService* local_state,
                         base::OnceCallback<void(std::optional<bool>)> done) {
  // ⚠️ Appel BLOQUANT côté OS (LaunchServices, registre Windows) : jamais sur
  // le fil de l'interface.
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&shell_integration::GetDefaultBrowser),
      base::BindOnce(
          [](base::OnceCallback<void(std::optional<bool>)> done,
             shell_integration::DefaultWebClientState state) {
            std::optional<bool> answer;
            if (state == shell_integration::IS_DEFAULT) {
              answer = true;
            } else if (state == shell_integration::NOT_DEFAULT ||
                       state == shell_integration::OTHER_MODE_IS_DEFAULT) {
              answer = false;
            }
            // ⚠️ Relu au retour, pas capturé à l'aller : la réponse peut
            // arriver pendant l'arrêt du navigateur.
            PrefService* local_state =
                g_browser_process ? g_browser_process->local_state() : nullptr;
            if (answer.has_value() && local_state) {
              RecordDefaultAnswer(local_state, *answer);
            }
            std::move(done).Run(answer);
          },
          std::move(done)));
}

void RecordDefaultProofForTesting(PrefService* local_state) {
  ScopedDictPrefUpdate update(local_state, prefs::kUsage);
  RollDay(update.Get(), local_state);
  InsertDay(update.Get(), kProofDays, LocalDayKey(base::Time::Now()));
}

void SetPagesTodayForTesting(PrefService* local_state, int pages) {
  ScopedDictPrefUpdate update(local_state, prefs::kUsage);
  RollDay(update.Get(), local_state);
  update->Set(kPages, pages);
}

void ResetUsageForTesting(PrefService* local_state) {
  local_state->ClearPref(prefs::kUsage);
}

base::DictValue UsageSnapshot(PrefService* local_state) {
  base::DictValue snapshot;
  if (!local_state) {
    return snapshot;
  }
  {
    // Le jour roule aussi à la lecture : un Nouvel Onglet ouvert au réveil,
    // avant toute page, ne doit pas lire les pages d'hier.
    ScopedDictPrefUpdate update(local_state, prefs::kUsage);
    RollDay(update.Get(), local_state);
  }
  const base::DictValue& usage = local_state->GetDict(prefs::kUsage);
  snapshot.Set("day", LocalDayKey(base::Time::Now()));
  snapshot.Set("pagesToday", usage.FindInt(kPages).value_or(0));
  const int baseline = usage.FindInt(kMusicBaseline).value_or(0);
  snapshot.Set("musicSecondsToday",
               std::max(0, MusicTotal(local_state) - baseline));
  snapshot.Set("browsingDays", usage.FindList(kBrowsingDays)
                                   ? usage.FindList(kBrowsingDays)->Clone()
                                   : base::ListValue());
  snapshot.Set("proofDays", usage.FindList(kProofDays)
                                ? usage.FindList(kProofDays)->Clone()
                                : base::ListValue());
  if (const std::optional<bool> is_default = usage.FindBool(kIsDefault)) {
    snapshot.Set("isDefault", *is_default);
  }
  return snapshot;
}

}  // namespace browther_referral
