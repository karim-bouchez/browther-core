// Copyright (c) 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'

import * as S from './style'
import Button from '@brave/leo/react/button'
import { WelcomeBrowserProxyImpl } from '../../api/welcome_browser_proxy'
import { getLocale, formatLocale } from '$web-common/locale'
import { loadTimeData } from '$web-common/loadTimeData'
import DataContext from '../../state/context'
import { useViewTypeTransition } from '../../state/hooks'

interface InputCheckboxProps {
  onChange?: (e: React.ChangeEvent<HTMLInputElement>) => void
  children: React.ReactNode
  id?: string
  isChecked: boolean
}

const changeSettingsNote = formatLocale('braveWelcomeChangeSettingsNote', {
  $1: content => <a href="browther://settings/privacy" onClick={() => {
    WelcomeBrowserProxyImpl.getInstance().openSettingsPage()
  }}>
    {content}
  </a>
})

const readPrivacyPolicy = formatLocale('braveWelcomePrivacyPolicyNote', {
  $1: content => <a href='https://browther.devndin.com/privacy' target='_blank'>
    {content}
  </a>
})

const diagnosticReportsLabel = formatLocale('braveWelcomeSendReportsLabel', {
  $1: content => <a href='https://browther.devndin.com/privacy' target='_blank'>
    {content}
  </a>
})

const braveProductUsageDataLabel = formatLocale('braveWelcomeSendInsightsLabel', {
  $1: content => <a href='https://browther.devndin.com/privacy' target='_blank'>
    {content}
  </a>
})

function InputCheckbox(props: InputCheckboxProps) {
  return (
    <label className="item">
      <input
        type="checkbox"
        checked={props.isChecked}
        onChange={props.onChange}
      />
      <div>
        {props.children}
      </div>
    </label>
  )
}

function HelpImprove() {
  const [isMetricsReportingEnabled, setMetricsReportingEnabled] = React.useState(true)
  const [isP3AEnabled, setP3AEnabled] = React.useState(true)
  // Browther : cet écran n'est plus le dernier — il passe la main à
  // `FollowChannels`, qui porte maintenant la sortie de l'onboarding
  // (`getWelcomeCompleteURL`). Le nom du bouton ne change pas : le
  // consentement analytics, lui, est bien terminé ici.
  const { viewType, setViewType } = React.useContext(DataContext)
  const { forward } = useViewTypeTransition(viewType)

  // Show toggles only if the preference is not managed by policy
  const showMetricsToggle = !loadTimeData.getBoolean('isMetricsReportingEnabledManaged')
  // <if expr="is_brave_origin_branded">
  // Brave Origin: never show P3A toggle
  const showP3AToggle = false
  // <else>
  const showP3AToggle = !loadTimeData.getBoolean('isP3AEnabledManaged')
  // </if>

  const handleP3AChange = () => {
    setP3AEnabled(!isP3AEnabled)
  }

  const handleMetricsReportingChange = () => {
    setMetricsReportingEnabled(!isMetricsReportingEnabled)
  }

  const handleFinish = () => {
    // Only set preferences if they're not managed by policy
    if (showP3AToggle) {
      WelcomeBrowserProxyImpl.getInstance().setP3AEnabled(isP3AEnabled)
    }
    if (showMetricsToggle) {
      WelcomeBrowserProxyImpl.getInstance().setMetricsReportingEnabled(isMetricsReportingEnabled)
    }
    // `onboarding_completed` reste émis **ici** et pas à la dernière étape :
    // c'est ici que se termine le parcours obligatoire (le consentement
    // analytics). Le déplacer plus loin ferait chuter le taux de complétion
    // historique du seul fait que l'étape « canaux » a été ajoutée après, et
    // rendrait la série incomparable avant/après.
    WelcomeBrowserProxyImpl.getInstance().trackOnboardingEvent('onboarding_completed', {
      sentry_enabled: isMetricsReportingEnabled,
      posthog_enabled: isP3AEnabled
    })
    setViewType(forward)
  }

  // Auto-finish if both settings are managed (no toggles to show)
  React.useEffect(() => {
    if (!showMetricsToggle && !showP3AToggle) {
      handleFinish()
    }
  }, [])

  // If both are managed, don't render anything since we auto-finish
  if (!showMetricsToggle && !showP3AToggle) {
    return null
  }

  // <if expr="is_brave_origin_branded">
  const title = getLocale('braveWelcomeStabilityDiagnosticsTitle')
  // <else>
  const title = getLocale('braveWelcomeHelpImproveBraveTitle')
  // </if>

  return (
    <S.MainBox>
      <div className="view-header-box">
        <div className="view-details">
          <h1 className="view-title">{title}</h1>
        </div>
      </div>
      <S.Grid>
        <div className="list">
          {showMetricsToggle && (
            <InputCheckbox
              id="metrics"
              onChange={handleMetricsReportingChange}
              isChecked={isMetricsReportingEnabled}
            >
              {diagnosticReportsLabel}
            </InputCheckbox>
          )}
          {showP3AToggle && (
            <InputCheckbox
              id="p3a"
              onChange={handleP3AChange}
              isChecked={isP3AEnabled}
            >
              {braveProductUsageDataLabel}
            </InputCheckbox>
          )}
        </div>
      </S.Grid>
      <S.ActionBox>
        <div className="box-center">
          <Button
            kind="filled"
            onClick={handleFinish}
            size="large"
          >
            {getLocale('braveWelcomeFinishButtonLabel')}
          </Button>
          <S.FootNote>
            {changeSettingsNote}
            <span>
              {readPrivacyPolicy}
            </span>
          </S.FootNote>
        </div>
      </S.ActionBox>
    </S.MainBox>
  )
}

export default HelpImprove
