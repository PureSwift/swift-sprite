#!/usr/bin/env python3
"""Exercise the built viewer with checked-in fixtures and SDL's headless backend."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('viewer', type=Path, help='Path to the built sprite-viewer executable')
    args = parser.parse_args()
    viewer = args.viewer.resolve(strict=True)
    fixtures = Path(__file__).resolve().parents[1] / 'Tests/SpriteFormatsTests/Fixtures'
    archives = fixtures / 'SceneArchives'
    passed = 0
    with tempfile.TemporaryDirectory(prefix='sprite-viewer-smoke-') as directory:
        root = Path(directory)
        env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_RENDER_DRIVER='software',
                   SWIFT_BACKTRACE='enable=no', LLVM_PROFILE_FILE=str(root / 'coverage.profraw'))

        def check(label, options, error=None):
            nonlocal passed
            result = subprocess.run([str(viewer), *map(str, options)], env=env, cwd=root,
                                    capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            valid = (result.returncode != 0 and error in output) if error else (
                result.returncode == 0 and 'Rendered 3 frames.' in result.stdout)
            if not valid:
                raise RuntimeError(f'{label}: exit {result.returncode}\n{output}')
            passed += 1
            print(f'PASS: {label}')
            return output

        def scene_options(path):
            return ['--sks', path, '--frames', '3']

        mappings = ['--class', 'FixtureGameScene=SKScene', '--class', 'FixtureGameSprite=SKSpriteNode']
        check('custom classes', scene_options(archives / 'custom-classes.sks') + mappings)
        sound_options = scene_options(archives / 'sound-actions.sks')
        check('sound requires explicit mute', sound_options, 'missingSound')
        muted = check('muted sound actions', sound_options + ['--mute'])
        if muted.count('Muted archived sound: beep.wav') != 1:
            raise RuntimeError('Expected one diagnostic for the shared muted sound')
        check('mute requires archive', ['--mute', '--frames', '3'], '--mute may be supplied once')
        check('duplicate mute', sound_options + ['--mute', '--mute'], '--mute may be supplied once')
        check('unmapped class', scene_options(archives / 'custom-classes.sks'), 'Node class')
        check('duplicate mapping', scene_options(archives / 'custom-classes.sks') + mappings +
              ['--class', 'FixtureGameScene=SKNode'], 'Duplicate --class')
        check('invalid frame count', ['--frames', '0'], '--frames requires')
        check('duplicate frame option', ['--frames', '3', '--frames', '4'], '--frames requires')
        for name in ['compound-physics', 'edge-physics', 'pinned-physics', 'color-actions', 'axis-scale-actions', 'resize-actions', 'size-scale-actions']:
            check(name, scene_options(archives / (name + '.sks')))

        scene = root / 'scene.sks'
        target = root / 'ReferenceTarget.sks'
        shutil.copyfile(archives / 'references.sks', scene)
        shutil.copyfile(archives / 'custom-classes.sks', target)
        check('references with class mappings', scene_options(scene) + mappings)
        shutil.copyfile(archives / 'sound-actions.sks', target)
        muted = check('muted sound in shared references', scene_options(scene) + ['--mute'])
        if muted.count('Muted archived sound: beep.wav') != 1:
            raise RuntimeError('Referenced scenes must share the muted sound resolver cache')
        shutil.copyfile(archives / 'custom-classes.sks', target)
        with scene.open('rb') as stream:
            reference_archive = plistlib.load(stream)
        reference_archive['$objects'] = [
            'ReferenceTarget.sks' if value == 'ReferenceTarget' else value
            for value in reference_archive['$objects']]
        with scene.open('wb') as stream:
            plistlib.dump(reference_archive, stream, fmt=plistlib.FMT_BINARY)
        check('explicit reference extension', scene_options(scene) + mappings)
        target.unlink()
        check('missing reference', scene_options(scene), 'missingReference')
        shutil.copyfile(scene, target)
        check('cyclic reference', scene_options(scene), 'Cyclic reference node')

        # Derive an atlas reference from a native fixture without modifying repository assets.
        with (archives / 'reference-target.sks').open('rb') as stream:
            atlas_archive = plistlib.load(stream)
        objects = atlas_archive['$objects']
        textures = [value for value in objects if isinstance(value, dict) and '$class' in value
                    and objects[value['$class'].data].get('$classname') == 'SKTexture']
        if not textures:
            raise RuntimeError('Reference fixture contains no texture to exercise')
        for texture in textures:
            texture['_originalAtlasName'] = 'sample'
            texture['_subTextureName'] = 'wide.png'
        with scene.open('wb') as stream:
            plistlib.dump(atlas_archive, stream, fmt=plistlib.FMT_BINARY)
        for extension in ['atlas', 'atlasc']:
            check(extension, scene_options(scene) + ['--atlas', fixtures / ('SpriteKit/sample.' + extension)])
        check('missing atlas', scene_options(scene), 'supply --atlas')
        check('missing atlas argument', scene_options(scene) + ['--atlas'], '--atlas requires')
        check('duplicate atlas name', scene_options(scene) + [
            '--atlas', fixtures / 'SpriteKit/sample.atlas', '--atlas', fixtures / 'SpriteKit/sample.atlasc'],
            'Duplicate atlas name')
        for texture in textures:
            texture['_subTextureName'] = 'missing.png'
        with scene.open('wb') as stream:
            plistlib.dump(atlas_archive, stream, fmt=plistlib.FMT_BINARY)
        check('missing atlas entry', scene_options(scene) + ['--atlas', fixtures / 'SpriteKit/sample.atlas'],
              'sample/missing')
    print(f'{passed} viewer smoke checks passed.')


if __name__ == '__main__':
    main()
