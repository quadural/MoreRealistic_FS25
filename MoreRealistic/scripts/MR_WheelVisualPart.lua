WheelVisualPart.mrLoadFromXML = function(self, superFunc, xmlObject, key)

    local result = superFunc(self, xmlObject, key)

    if result then
        if self.name == "additional" and self.mass~=nil and self.mass>0 then
            --check if his is a wheel ironcast ballast object
            local fullScaleMass = 0
            local commonKey = "data/shared/wheels/weights/"
            if self.filename==commonKey.."weight001.i3d" then
                if string.sub(self.indexPath,1,1)=="0" then
                    fullScaleMass = 0.6
                elseif string.sub(self.indexPath,1,1)=="1" then
                    fullScaleMass = 1.35
                end
            elseif self.filename==commonKey.."weight002.i3d" then
                if string.sub(self.indexPath,1,1)=="0" then
                    fullScaleMass = 0.65
                elseif string.sub(self.indexPath,1,1)=="1" then
                    fullScaleMass = 1.1
                end
            elseif self.filename==commonKey.."weight003.i3d" then
                fullScaleMass = 1.2
            elseif self.filename==commonKey.."weight004.i3d" then
                fullScaleMass = 1.3
            elseif self.filename==commonKey.."weight005.i3d" then
                if string.sub(self.indexPath,1,1)=="0" then
                    fullScaleMass = 0.88
                elseif string.sub(self.indexPath,1,1)=="1" then
                    fullScaleMass = 0.3
                elseif string.sub(self.indexPath,1,1)=="2" then
                    fullScaleMass = 0.075
                elseif string.sub(self.indexPath,1,1)=="3" then
                    fullScaleMass = 0.3
                end
            elseif self.filename==commonKey.."weight006.i3d" then
                fullScaleMass = 0.68
            elseif self.filename==commonKey.."weight007.i3d" then
                fullScaleMass = 0.54
            elseif self.filename==commonKey.."weight008.i3d" then
                fullScaleMass = 0.105
            elseif self.filename==commonKey.."/cnh/weight001.i3d" then
                fullScaleMass = 0.6
            end
            if fullScaleMass>0 then
                self.mass = fullScaleMass * self.scale[1] * self.scale[2] * self.scale[3]
            end
        end
    end

    return result

end
WheelVisualPart.loadFromXML = Utils.overwrittenFunction(WheelVisualPart.loadFromXML, WheelVisualPart.mrLoadFromXML)