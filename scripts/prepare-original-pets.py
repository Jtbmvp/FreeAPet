#!/usr/bin/env python3
"""Build a source-verified, INACTIVE original-pet catalog; never edit GLBs or UI.
No Studio calls, source rig re-export, old anchors, animation uploads or roster edits.
"""
from pathlib import Path
import hashlib,json,struct
ROOT=Path(__file__).resolve().parents[1]
REVIEW=ROOT/'design/reviews/asset-readiness-2026-11-03'
OUT=ROOT/'design/coder/original-pets-prep-2026-11-03'
CATALOG=ROOT/'src/shared/OriginalPets/Catalog.luau'

def lua(value,depth=0):
    if value is None:return 'nil'
    if value is True:return 'true'
    if value is False:return 'false'
    if isinstance(value,(int,float)):return str(value)
    if isinstance(value,str):return json.dumps(value,ensure_ascii=False)
    if isinstance(value,list):return '{ '+', '.join(lua(v,depth+1) for v in value)+' }'
    return '{\n'+''.join('\t'*(depth+1)+'['+lua(k)+'] = '+lua(v,depth+1)+',\n' for k,v in value.items())+'\t'*depth+'}'

def glb_json(raw):
    magic,version,length=struct.unpack_from('<4sII',raw)
    assert magic==b'glTF' and version==2 and length==len(raw),'Invalid GLB header'
    size,kind=struct.unpack_from('<II',raw,12)
    assert kind==0x4e4f534a,'First GLB chunk must be JSON'
    return json.loads(raw[20:20+size])

def main():
    handoff=json.loads((REVIEW/'pet-originals-upload-contract.json').read_text())
    manifest_path=ROOT/'design/glb-upload-2026-11-03/glb_asset_ids.json'
    manifest_raw=manifest_path.read_bytes();manifest=json.loads(manifest_raw)
    assert hashlib.sha256(manifest_raw).hexdigest()==handoff['manifestSha256'],'Upload manifest changed: review identity before regeneration'
    variants={};source_hashes={};assemblies=[];all_model_ids={};report=[]
    for f in sorted(handoff['files'],key=lambda e:e['file']):
        path=ROOT/'Free a Pet Models-1'/f['file'];raw=path.read_bytes();digest=hashlib.sha256(raw).hexdigest()
        uploaded=manifest[f['file']]
        assert digest==f['sourceSha256']==uploaded['sha256'],f['file']
        assert str(uploaded['assetId'])==f['uploadedAssetId'],f['file']
        assert uploaded['state']=='Active' and uploaded['moderation']=='Approved',f['file']
        all_model_ids[f['uploadedAssetId']]=True;source_hashes[str(path.relative_to(ROOT))]=digest
        if f['variant'] not in ['Baby','Juvenile','Adult']:
            assemblies.append({'file':f['file'],'assetId':f['uploadedAssetId'],'sha256':digest});continue
        g=glb_json(raw);assert len(g.get('skins',[]))==1,f['file']
        joints=g['skins'][0]['joints'];names=[g['nodes'][i]['name'] for i in joints]
        assert len(names)==len(set(names)) and set(names)==set(f['skins'][0]['bones']),f['file']
        assert 'jnt_hips' in names
        parent={c:i for i,n in enumerate(g['nodes']) for c in n.get('children',[])}
        expected_parents={g['nodes'][i]['name']:g['nodes'][parent[i]]['name'] for i in joints if parent.get(i) in joints}
        rigid=[]
        for node_id,node in enumerate(g['nodes']):
            if 'mesh' not in node or 'skin' in node:continue
            ancestor=parent.get(node_id)
            while ancestor is not None and ancestor not in joints:ancestor=parent.get(ancestor)
            rigid.append({'node':node_id,'name':node.get('name',''), 'nearestSkinBone':g['nodes'][ancestor]['name'] if ancestor is not None else None})
        clips={}
        for animation in g['animations']:
            channels={p:[] for p in ['translation','rotation','scale']}
            for ch in animation['channels']:
                p=ch['target']['path'];target=ch['target'].get('node')
                assert p in channels and target is not None
                channels[p].append(g['nodes'][target]['name'])
                sampler=animation['samplers'][ch['sampler']]
                assert sampler.get('interpolation','LINEAR') in ['LINEAR','STEP']
            evidence=next(c for c in f['allClips'] if c['name']==animation['name'])
            clips[animation['name']]={'duration':evidence['durationSeconds'],'loop':animation['name'] in ['Idle','Walk'],'scaleChannels':sorted(set(channels['scale'])),'knownRotationSeamDegrees':evidence['rotationEndpointSeamDegrees']}
        assert 'Idle' in clips and 'Walk' in clips and len(clips)==5
        key=f["speciesSlug"]+'/'+f['variant']
        variants[key]={'key':key,'slug':f['speciesSlug'],'stage':f['variant'],'runtimeSpeciesId':f['currentRuntimeSpeciesId'],'modelAssetId':f['uploadedAssetId'],'sourceSha256':digest,'sourceFile':f['file'],'sourceHeightMetres':f['staticHeightMetres'],'adultHeightStuds':f['adultTargetHeightStudsFromCurrentConfig'],'visualYawDegrees':180,'bones':names,'boneParents':expected_parents,'clips':clips}
        report.append({'key':key,'sourceSha256':digest,'bones':len(names),'clips':len(clips),'rigidMeshesRequiringNativeAttachmentVerification':rigid,'idleScaleChannels':clips['Idle']['scaleChannels'],'walkScaleChannels':clips['Walk']['scaleChannels'],'runtimeSpeciesId':f['currentRuntimeSpeciesId']})
    assert len(variants)==27 and len(assemblies)==9
    data={'version':1,'active':False,'sourceManifestSha256':handoff['manifestSha256'],'modelAssetIds':all_model_ids,'variants':variants}
    CATALOG.parent.mkdir(parents=True,exist_ok=True)
    CATALOG.write_text('--!strict\n-- GENERATED by scripts/prepare-original-pets.py. INACTIVE; no runtime registration.\n-- Model asset IDs are NOT AnimationIds. Never bind legacy clips to these skins.\nreturn '+lua(data)+'\n')
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'source-verification.json').write_text(json.dumps({'originalsUnmodified':True,'verifiedSourceHashes':source_hashes,'variantCount':len(variants),'referenceAssemblyCount':len(assemblies),'variants':report,'pendingSpeciesMapping':sorted({f['speciesSlug'] for f in handoff['files'] if not f['currentRuntimeSpeciesId']}),'nativeAnimationIdsProvided':False,'studioTouched':False},indent=2)+'\n')
    (OUT/'reference-assemblies.json').write_text(json.dumps(assemblies,indent=2)+'\n')
    print(f'PASS: {len(source_hashes)} original hashes verified; {len(variants)} individual variants cataloged, {len(assemblies)} assemblies excluded from runtime candidates')
if __name__=='__main__':main()
