import { send } from "./wick";

export default async function main() {
  await send("stop", undefined, "Wick stopped");
}
