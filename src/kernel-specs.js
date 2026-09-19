export const UNITS=['common','terrain','shrubs','ocean','render'];
export const SPECS=[
 {entry:'cacheShrubs',file:'shrubs',workgroupSize:[8,8,1],dependencies:['common','terrain','shrubs']},
 {entry:'cacheOceanSpectrum',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','ocean']},
 {entry:'advanceOceanSpectrum',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','ocean']},
 {entry:'seedOcean',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','ocean']},
 {entry:'oceanFft',file:'ocean',workgroupSize:[128,1,1],dependencies:['common','ocean']},
 {entry:'packOcean',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','ocean']},
 {entry:'oceanMip',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','ocean']},
 {entry:'tracePrimary',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'traceVegetation',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'reflectOcean',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'shadeOcean',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'probeWorld',file:'render',workgroupSize:[64,1,1],dependencies:UNITS}
];
export const compilerOptions=spec=>({entry:spec.entry,workgroupSize:spec.workgroupSize,optimize:'specialize'});
