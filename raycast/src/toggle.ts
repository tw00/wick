import { send } from "./wick";

export default async function main() {
  await send("toggle", undefined, "Wick toggled");
}
