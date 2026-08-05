/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `start` command */
  export type Start = ExtensionPreferences & {}
  /** Preferences accessible in the `toggle` command */
  export type Toggle = ExtensionPreferences & {}
  /** Preferences accessible in the `add` command */
  export type Add = ExtensionPreferences & {}
  /** Preferences accessible in the `stop` command */
  export type Stop = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `start` command */
  export type Start = {
  /** 25m */
  "duration": string
}
  /** Arguments passed to the `toggle` command */
  export type Toggle = {}
  /** Arguments passed to the `add` command */
  export type Add = {
  /** 5m */
  "duration": string
}
  /** Arguments passed to the `stop` command */
  export type Stop = {}
}

