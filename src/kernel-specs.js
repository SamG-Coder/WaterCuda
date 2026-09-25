export const UNITS=['common','weather','terrain','terrain-cache','shrubs','ocean','ship','render'];
export const MOBILE_UNITS=['common','terrain','terrain-cache','ocean','mobile-render'];
export const SPECS=[
 {entry:'traceMobile',file:'mobile-render',workgroupSize:[8,8,1],dependencies:MOBILE_UNITS},
 {entry:'shadeMobile',file:'mobile-render',workgroupSize:[8,8,1],dependencies:MOBILE_UNITS},
 {entry:'cacheTerrain',file:'terrain-cache',workgroupSize:[8,8,1],dependencies:['common','terrain','terrain-cache']},
 {entry:'mipTerrain',file:'terrain-cache',workgroupSize:[8,8,1],dependencies:['common','terrain','terrain-cache']},
 {entry:'generateShrubAtlas',file:'shrubs',workgroupSize:[8,8,1],dependencies:['common','weather','terrain','shrubs']},
 {entry:'mipShrubAtlas',file:'shrubs',workgroupSize:[8,8,1],dependencies:['common','weather','terrain','shrubs']},
 {entry:'cacheShrubs',file:'shrubs',workgroupSize:[8,8,1],dependencies:['common','weather','terrain','shrubs']},
 {entry:'cacheOceanSpectrum',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','weather','ocean']},
 {entry:'advanceOceanSpectrum',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','weather','ocean']},
 {entry:'seedOcean',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','weather','ocean']},
 {entry:'oceanFft',file:'ocean',workgroupSize:[128,1,1],dependencies:['common','weather','ocean']},
 {entry:'packOcean',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','weather','ocean']},
 {entry:'oceanMip',file:'ocean',workgroupSize:[8,8,1],dependencies:['common','weather','ocean']},
 {entry:'cacheReef',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'stepShipWater',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'updateShip',file:'render',workgroupSize:[1,1,1],dependencies:UNITS},
 {entry:'tracePrimary',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'traceVegetation',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'reflectOcean',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'shadeOcean',file:'render',workgroupSize:[8,8,1],dependencies:UNITS},
 {entry:'probeWorld',file:'render',workgroupSize:[64,1,1],dependencies:UNITS}
];
export const compilerOptions=spec=>({entry:spec.entry,workgroupSize:spec.workgroupSize,optimize:'specialize'});
