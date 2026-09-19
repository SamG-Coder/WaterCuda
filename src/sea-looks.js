// Look changes are small uniform updates, never shader recompiles or mesh swaps.
export const SEA_LOOKS=Object.freeze({
 coastal:Object.freeze({name:'Clear coast',wind:1,sunAzimuth:-.7,sunHeight:.7,exposure:1,clarity:1.5}),
 golden:Object.freeze({name:'Golden hour',wind:.65,sunAzimuth:1.05,sunHeight:.16,exposure:.95,clarity:1.3}),
 swell:Object.freeze({name:'Open sea swell',wind:1.85,sunAzimuth:-.45,sunHeight:.48,exposure:.94,clarity:.7})
});
export function applySeaLook(camera,name){
 const look=SEA_LOOKS[name];if(!look)throw new RangeError('Unknown sea look: '+name);
 if(!camera||camera.length<14)throw new TypeError('A camera/control buffer with at least 14 floats is required.');
 camera[6]=look.wind;camera[7]=look.sunAzimuth;camera[8]=look.sunHeight;camera[11]=look.exposure;camera[12]=look.clarity;
 return look;
}
