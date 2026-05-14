// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

// Browther: réplique React/CSS du `BrowtherBigToggle` natif (Sawtunaa popup)
// et du big toggle CSS du panel Basarunaa, pour uniformiser visuellement les
// 3 popups (Sawtunaa, Basarunaa, Bouclier Browther). Identique aux 6
// keyframes de iOS ShieldsSwitch.swift::steps, cycle 4.5s. Couleurs
// interpolées en continu via `@property syntax: '<color>'`.

import * as React from 'react'
import styled, { keyframes, css } from 'styled-components'

interface Props {
  checked: boolean
  disabled?: boolean
  onChange: (checked: boolean) => void
  ariaLabel?: string
}

const greenCycle = keyframes`
  0%   { --grad-inner: #86EFAC; --grad-outer: #4ADE80; }
  16.6%{ --grad-inner: #4ADE80; --grad-outer: #22C55E; }
  33.3%{ --grad-inner: #22C55E; --grad-outer: #16A34A; }
  50%  { --grad-inner: #16A34A; --grad-outer: #10B981; }
  66.6%{ --grad-inner: #10B981; --grad-outer: #34D399; }
  83.3%{ --grad-inner: #34D399; --grad-outer: #86EFAC; }
  100% { --grad-inner: #86EFAC; --grad-outer: #4ADE80; }
`

interface ToggleButtonProps { $on: boolean; $disabled: boolean }

const ToggleButton = styled.button<ToggleButtonProps>`
  /* Variables typées pour interpolation continue des couleurs du gradient. */
  @property --grad-inner {
    syntax: '<color>';
    inherits: false;
    initial-value: #86EFAC;
  }
  @property --grad-outer {
    syntax: '<color>';
    inherits: false;
    initial-value: #4ADE80;
  }

  width: 96px;
  height: 52px;
  border-radius: 26px;
  position: relative;
  cursor: ${p => p.$disabled ? 'not-allowed' : 'pointer'};
  background: #555;
  transition: background 0.3s ease;
  border: none;
  padding: 0;
  outline: none;
  opacity: ${p => p.$disabled ? 0.5 : 1};

  &::before {
    content: '';
    position: absolute;
    top: 6px;
    left: 6px;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: white;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
    transition: transform 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
  }

  &:focus-visible {
    box-shadow: 0 0 0 3px rgba(134, 239, 172, 0.4);
  }

  ${p => p.$on && css`
    background: radial-gradient(circle at bottom right,
                                var(--grad-inner), var(--grad-outer));
    animation: ${greenCycle} 4.5s linear infinite;

    &::before {
      transform: translateX(44px);
    }
  `}
`

export default function BrowtherBigToggle (props: Props) {
  const onClick = () => {
    if (props.disabled) return
    props.onChange(!props.checked)
  }
  return (
    <ToggleButton
      type='button'
      $on={props.checked}
      $disabled={!!props.disabled}
      onClick={onClick}
      aria-pressed={props.checked}
      aria-label={props.ariaLabel ?? 'Toggle'}
      disabled={props.disabled}
    />
  )
}
