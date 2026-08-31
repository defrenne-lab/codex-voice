import Foundation

do {
  let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
  try ProbeRunner(options: options).run()
} catch {
  FileHandle.standardError.write(Data("Erreur : \(error.localizedDescription)\n".utf8))
  exit(1)
}
