import { GenericContainer, Wait } from "testcontainers";

const container = await new GenericContainer("alpine:3.22.2")
  .withCommand(["sh", "-c", "echo integration-ready && sleep 60"])
  .withWaitStrategy(Wait.forLogMessage("integration-ready"))
  .start();

try {
  const result = await container.exec(["echo", "container-output-ok"]);
  console.log(result.output.trim());
  if (!result.output.includes("container-output-ok") || result.exitCode !== 0) {
    console.error("The container output is wrong.");
    process.exitCode = 1;
  }
} finally {
  await container.stop();
}
