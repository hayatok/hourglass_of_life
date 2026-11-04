"""Authored proportions shared by geometry, rest bones, morphs and animation translation.
Profile dimensions are fictional art decisions. They are not population measurements.
"""
import json
from pathlib import Path
from mathutils import Vector,Matrix

class Dimensions:
    def __init__(self,root):
        file=Path(root)/'profile.json'
        self.profile=json.loads(file.read_text()) if file.exists() else {}
        self.height=self.profile.get('height',1.65)
        self.head_scale=self.profile.get('head_scale',1.0)
        self.head_x=self.profile.get('head_x',1.0)
        self.width=self.profile.get('width',1.0)
        self.depth=self.profile.get('depth',1.0)
        self.lean=self.profile.get('lean',0.0)
        self.arm_length=self.profile.get('arm_length',1.0)
        self.arm_close=self.profile.get('arm_close',0.0)
        self.stance=self.profile.get('stance',0.0)
        self.shoe_stance=self.profile.get('shoe_stance',self.stance)
        self.shoulder_width=self.profile.get('shoulder_width',1.0)
        self.shoulder_z=self.profile.get('shoulder_z',1.27)
        self.foot_turn=self.profile.get('foot_turn',0.0)
        self.body_scale=(self.height-.27*self.head_scale)/1.38
        if min(self.body_scale,self.head_scale,self.head_x,self.width,self.depth,self.arm_length,self.shoulder_width)<=0:
            raise ValueError('All authored body dimensions must be positive')
        self.motion=self.profile.get('motion',{})
    def z(self,z):
        return z*self.body_scale if z<=1.38 else 1.38*self.body_scale+(z-1.38)*self.head_scale
    def x_scale(self,z):
        t=max(0,min(1,(z-1.30)/.1))
        shoulder=max(0,1-abs(z-self.shoulder_z)/.10)
        return (self.width*(1-t)+self.head_x*t)*(1+(self.shoulder_width-1)*shoulder)
    def to_model(self,co):
        x,y,z=co
        t=max(0,min(1,(abs(x)-(.12+.20*max(0,1.1-z)))/.06))
        t=t*t*(3-2*t)
        arm_z=1.3+(z-1.3)*(1+(self.arm_length-1)*t)
        arm_x=x-(1 if x>0 else -1)*self.arm_close*max(0,1.3-z)*t
        if z<.95:
            sign=max(-1,min(1,x/.04))
            region=max(0,min(1,(.24+.14*max(0,.85-z)-abs(x))/.04))
            stance=self.stance+(self.shoe_stance-self.stance)*max(0,min(1,(.20-z)/.08))
            arm_x+=sign*stance*max(0,min(1,(.95-z)/.75))*region
            if z<.13 and self.foot_turn:
                import math
                angle=sign*self.foot_turn*max(0,min(1,(.13-z)/.04))*region
                pivot=sign*(.077+stance)
                dx=arm_x-pivot
                arm_x=pivot+dx*math.cos(angle)-y*math.sin(angle)
                y=dx*math.sin(angle)+y*math.cos(angle)
        return Vector((arm_x*self.x_scale(z),y*self.depth-self.lean*max(0,z-1.05),self.z(arm_z)))
    def to_base(self,co):
        x,y,z=co
        z=z/self.body_scale if z<=1.38*self.body_scale else 1.38+(z-1.38*self.body_scale)/self.head_scale
        result=Vector((x/self.x_scale(z),(y+self.lean*max(0,z-1.05))/self.depth,z))
        if self.arm_length!=1 or self.arm_close!=0 or self.stance!=0 or self.foot_turn!=0:
            target=Vector(co)
            for _ in range(12):
                delta=target-self.to_model(result)
                if delta.length<1e-7:break
                point=self.to_model(result);columns=[]
                for axis in range(3):
                    probe=result.copy();probe[axis]+=.0001
                    columns.append((self.to_model(probe)-point)/.0001)
                jacobian=Matrix(columns).transposed()
                result+=jacobian.inverted_safe()@delta
        return result
