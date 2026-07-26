// SPDX-License-Identifier: Apache-2.0

import readline from "node:readline";

const lines = readline.createInterface({ input: process.stdin });
for await (const line of lines) {
  const message = JSON.parse(line);
  const args = message?.params?.arguments;
  const value = Array.isArray(args) ? args[0] : args?.v;
  const response = {
    jsonrpc: "2.0",
    id: message.id,
    result: {
      content: [{
        type: "text",
        text: `observer received v=${String(value)}`,
      }],
      isError: false,
    },
  };
  process.stdout.write(`${JSON.stringify(response)}\n`);
}
