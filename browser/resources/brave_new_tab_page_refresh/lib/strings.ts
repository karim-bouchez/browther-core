/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import { getLocale } from '$web-common/locale'
import '$web-common/strings'

import {
  BraveNewsStrings,
  BraveNewTabPageStrings,
  BraveRewardsStrings,
  BraveOmniboxStrings,
} from 'gen/components/grit/brave_components_webui_strings'

declare global {
  interface Strings {
    BraveNewTabPageStrings: typeof BraveNewTabPageStrings
    // Browther: BraveNewsStrings ajouté ici. À l'origine enregistré indirectement
    // via LazyNewsFeed (qui importait components/brave_news/.../strings.ts).
    // On a retiré LazyNewsFeed (News disabled) mais widget_stack.tsx importe
    // toujours news_widget.tsx pour le typing → TS a besoin de BraveNewsStrings.
    BraveNewsStrings: typeof BraveNewsStrings
    BraveRewardsStrings: typeof BraveRewardsStrings
    BraveOmniboxStrings: typeof BraveOmniboxStrings
  }
}

export type StringKey =
  | BraveNewTabPageStrings
  | BraveNewsStrings
  | BraveRewardsStrings
  | BraveOmniboxStrings

export function getString(key: StringKey) {
  return getLocale(key)
}
