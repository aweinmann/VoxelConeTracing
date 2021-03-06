/*
 Copyright (c) 2012 The VCT Project

  This file is part of VoxelConeTracing and is an implementation of
  "Interactive Indirect Illumination Using Voxel Cone Tracing" by Crassin et al

  VoxelConeTracing is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  VoxelConeTracing is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with VoxelConeTracing.  If not, see <http://www.gnu.org/licenses/>.
*/

/*!
* \author Dominik Lazarek (dominik.lazarek@gmail.com)
* \author Andreas Weinmann (andy.weinmann@gmail.com)
*/

#version 420

in VertexData {
  vec3 viewDirVS;
  float pixelSizeVS;
  vec2 uv;
} In;

out vec4 outColor;

uniform sampler3D brickPool_color;
uniform sampler3D brickPool_normal;
uniform sampler3D brickPool_irradiance; 

uniform sampler2D gBuffer_color;
uniform sampler2D gBuffer_pos;
uniform sampler2D gBuffer_normal;
uniform sampler2D gBuffer_tangent;
uniform sampler2D shadowMap;

layout(r32ui) uniform readonly uimageBuffer nodePool_next;
layout(r32ui) uniform readonly uimageBuffer nodePool_color;

uniform vec3 lightDir;
uniform mat4 lightCamProjMat;
uniform mat4 lightCamviewMat;

uniform uint voxelGridResolution;
uniform mat4 viewI;
uniform mat4 voxelGridTransformI;
uniform uint numLevels;


// Tweak-parameters
uniform float giIntensity;
uniform float specGiIntensity;
uniform float specExponent;
uniform float coneAngle;
uniform float coneMaxDistance;
uniform bool useLighting = true;
uniform bool renderAO = false;

#include "assets/shader/_utilityFunctions.shader"
#include "assets/shader/_octreeTraverse.shader"
#include "assets/shader/_coneTrace.shader"

const float PI = 3.1415926535897932384626433832795;

float tanAngleDeg(in float angleDeg) {
   return abs(tan((angleDeg / 180.0) * PI * 0.5));
}


vec4 gatherIndirectIllum(in vec3 posTex, in vec3 normal, in vec3 tangent) {
  vec3 bitangent = cross(normal, tangent);

  vec4 color = vec4(0);

  
  float maxDist = 0.3;

  if (renderAO) {
    maxDist = 0.0001;
  }

  color += coneTrace(posTex, normal, coneAngle, maxDist);
  color += 0.707 * coneTrace(posTex, normalize(normal + tangent), coneAngle, maxDist);
  color += 0.707 * coneTrace(posTex, normalize(normal - tangent), coneAngle, maxDist);
  color += 0.707 * coneTrace(posTex, normalize(normal + bitangent), coneAngle, maxDist);
  color += 0.707 * coneTrace(posTex, normalize(normal - bitangent), coneAngle, maxDist);
  
  return color / 3.828;
}


void main(void)
{
  vec4 posWS = vec4(vec3(texture(gBuffer_pos, In.uv)),1);
  vec3 normalWS = texture(gBuffer_normal, In.uv).xyz;
  vec3 tangentWS = texture(gBuffer_tangent, In.uv).xyz;
  vec4 diffColor = vec4(texture(gBuffer_color, In.uv).xyz, 1.0);
  vec3 posTex = (voxelGridTransformI * posWS).xyz * 0.5 + 0.5; 
  


  if (renderAO) {
    vec4 indirectLight = gatherIndirectIllum(posTex, normalWS, tangentWS);
    outColor = vec4(1.0 - indirectLight.aaa, 1.0);
  }

  else {
    // Shadow mapping
   float visibility = 1.0;
   vec4 posLVS = lightCamviewMat * posWS;
   vec4 posLProj = lightCamProjMat * posLVS;
   posLProj.xyz /= posLProj.w;
   posLProj.xyz = posLProj.xyz * 0.5 + 0.5;

   vec3 lightIntensity = vec3(0);
   vec3 view = normalize(posWS.xyz - viewI[3].xyz);

   float e = 0.0008;
   if (useLighting) {
    if (abs(texture(shadowMap, posLProj.xy).x) + e < abs(posLProj.z)){
       visibility = 0.0;
     }

     // Light intensity
     vec3 h = normalize((-view) + lightDir);
     vec3 lightColor = vec3(1); /** giIntensity;  */ //TODO: Replace with uniform
   
     // Account for local shading      
     float diff = max(0.0, dot(lightDir, normalWS));
     float spec = pow(max(0.0, dot(normalWS, h)), specExponent);
     lightIntensity += visibility * (lightColor * diff + spec);
   }
   

   lightIntensity += giIntensity * gatherIndirectIllum(posTex, normalWS, tangentWS).xyz;
   vec3 reflectVec = normalize(reflect(view, normalWS));
   lightIntensity += specGiIntensity * coneTrace(posTex, reflectVec, 2.0 * tanAngleDeg(specExponent), 0.0).xyz;
   
   outColor = diffColor * vec4(lightIntensity, 1.0);
  }
}