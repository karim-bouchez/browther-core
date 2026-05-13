// Copyright (c) 2017 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import config from './config.js'
import util from './util.js'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import fs from 'fs-extra'
import Log from './logging.js'
import branding from './branding.js'

// Browther: post-build hook (Sentry symbols upload, future deploy-extensions, etc.)
// Best-effort, n'échoue jamais le build.
const runBrowtherPostBuildHook = () => {
  try {
    const variant = `${config.buildConfig}_${config.targetArch || 'arm64'}`
    const scriptPath = path.resolve(
      config.srcDir,
      '..', '..', 'private', 'scripts', 'post-build.sh',
    )
    if (!fs.existsSync(scriptPath)) {
      return // private/ pas présent (cas CI public, fork community)
    }
    const result = spawnSync(scriptPath, [variant], {
      stdio: 'inherit',
      env: process.env,
    })
    if (result.status !== 0) {
      Log.warn(`Browther post-build hook a échoué (variant=${variant}, status=${result.status}) — build OK quand même`)
    }
  } catch (err) {
    Log.warn(`Browther post-build hook a throw : ${err?.message || err} — build OK quand même`)
  }
}

/**
 * Checks to make sure the src/chrome/VERSION matches brave-core's package.json version
 */
const checkVersionsMatch = () => {
  const srcChromeVersionDir = path.resolve(
    path.join(config.srcDir, 'chrome', 'VERSION'),
  )
  const versionData = fs.readFileSync(srcChromeVersionDir, 'utf8')
  const re = /MAJOR=(\d+)\s+MINOR=(\d+)\s+BUILD=(\d+)\s+PATCH=(\d+)/
  const found = versionData.match(re)
  const braveVersionFromChromeFile = `${found[2]}.${found[3]}.${found[4]}`
  if (braveVersionFromChromeFile !== config.braveVersion) {
    // Only a warning. The CI environment will choose to proceed or not within its own script.
    Log.warn(
      `Version files do not match!\n`
        + `src/chrome/VERSION: ${braveVersionFromChromeFile}\n`
        + `brave-core configured version: ${config.braveVersion}\n`
        + `Did you forget to sync?`,
    )
  }
}

const build = async (buildConfig = config.defaultBuildConfig, options = {}) => {
  config.buildConfig = buildConfig
  config.update(options)
  checkVersionsMatch()

  util.touchOverriddenFiles()
  branding.update()
  await util.buildNativeRedirectCC()

  if (options.prepare_only) {
    return
  }

  if (config.xcode_gen_target) {
    util.generateXcodeWorkspace()
  } else {
    if (!config.use_no_gn_gen) {
      await util.generateNinjaFiles()
    }
    await util.buildTargets()
    // Browther: post-build hook
    runBrowtherPostBuildHook()
  }
}

export default build
