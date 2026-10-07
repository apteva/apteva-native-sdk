import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
if (git('status', '--porcelain')) throw new Error('Commit all SDK release source before packaging.');
const version = JSON.parse(readFileSync(join(root, 'contract/contract-version.json'), 'utf8')).version;
const commit = git('rev-parse', 'HEAD');
if (git('rev-list', '-n', '1', `v${version}`) !== commit) throw new Error('Release tag must point to HEAD.');
const relative = `ai/apteva/native-sdk/${version}`;
const source = join(homedir(), '.m2/repository', relative);
const output = join(root, 'build', 'release', version);
const repository = join(output, 'maven');
const destination = join(repository, relative);
mkdirSync(destination, { recursive: true });
const files = ['aar', 'pom', 'module'].map(ext => `native-sdk-${version}.${ext}`);
files.push(`native-sdk-${version}-sources.jar`);
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const pom = readFileSync(join(source, `native-sdk-${version}.pom`), 'utf8');
if (!pom.includes(`<artifactId>native-sdk</artifactId>`) || !pom.includes(`<version>${version}</version>`)) {
  throw new Error('Maven publication does not match the release identity.');
}
const metadata = JSON.parse(readFileSync(join(source, `native-sdk-${version}.module`), 'utf8'));
if (metadata.component.version !== version) throw new Error('Gradle metadata version mismatch.');
for (const variant of metadata.variants) {
  for (const artifact of variant.files ?? []) {
    if (hash(join(source, artifact.name)) !== artifact.sha256) throw new Error(`Stale artifact: ${artifact.name}`);
  }
}
for (const file of files) {
  copyFileSync(join(source, file), join(destination, file));
  copyFileSync(join(source, file), join(output, file));
}
const archive = `apteva-native-sdk-${version}-maven.zip`;
execFileSync('zip', ['-q', '-r', join(output, archive), relative], { cwd: repository });
files.push(archive);
const artifacts = Object.fromEntries(files.map(file => [file, { sha256: hash(join(output, file)) }]));
writeFileSync(join(output, 'release-manifest.json'), JSON.stringify({
  repository: 'https://github.com/apteva/apteva-native-sdk',
  version, tag: `v${version}`, commit,
  androidCoordinate: `ai.apteva:native-sdk:${version}`,
  artifacts,
}, null, 2) + '\n');
files.push('release-manifest.json');
writeFileSync(join(output, 'SHA256SUMS'), files.map(file => `${hash(join(output, file))}  ${file}`).join('\n') + '\n');
console.log(JSON.stringify({ version, commit, output, artifacts: [...files, 'SHA256SUMS'] }, null, 2));
