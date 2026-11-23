require("VersaUndercutTracker.domain.types")
local Paint = require("VersaUndercutTracker.ui.undercut_paint")

describe("ui undercut paint (pure parts)", function()
    it("normalizes both ScrollUtil callback signatures", function()
        local frame = { Text = {} }
        -- event path: (owner, frame, elementData) - owner is our nil
        local f, e = Paint.frameArgs(nil, frame, 3)
        assert.equals(frame, f)
        assert.equals(3, e)
        -- iterateExisting path through ForEachFrame: (frame, elementData)
        f, e = Paint.frameArgs(frame, 3)
        assert.equals(frame, f)
        assert.equals(3, e)
    end)
end)
