import Testing
import CoreImage
@testable import PinballVision

@Test func boundedTitleCorroborationDoesNotInventOtherModes() {
    #expect(agreesWithModeTitle("CASTLE GRUNENALD HIT CAPTIVE BALL",mode:"Castle Grunewald"))
    #expect(agreesWithModeTitle("ESCAPE IN THE MINE CART VIDEO MODE",mode:"Escape in the Mine Cart"))
    #expect(!agreesWithModeTitle("CASTLE GRUNENALD",mode:"Steal the Stones"))
    #expect(!agreesWithModeTitle("CASTLE GRUMENALX",mode:"Castle Grunewald"))
    #expect(!agreesWithModeTitle("THREE CHALLENGES",mode:"Tank Chase"))
}

@Test func samplingRespectsBoundsAndKnownTranslation() {
    var pixels=[Float](repeating:0,count:4096)
    pixels[15*128+60]=1
    let moved=shifted(pixels,dx:1,dy:-1)
    #expect(moved[16*128+59]==1)
    #expect(moved[15*128+60]==0)
    #expect(shifted(pixels,dx:1000,dy:1000).allSatisfy{$0==0})
    let softened=smooth(pixels)
    #expect(softened[15*128+60]>0.5)
    #expect(abs(softened.reduce(0,+)-1)<0.0001)
}

@Test func coreImagePixelLayoutAndRectificationAreConsistent() throws {
    let work=ImageWork()
    let image=CIImage(color:CIColor(red:1,green:0,blue:0)).cropped(to:CGRect(x:0,y:0,width:540,height:960))
    let crop=try work.rectified(image,corners:[CGPoint(x:100,y:400),CGPoint(x:400,y:400),CGPoint(x:400,y:500),CGPoint(x:100,y:500)],width:128,height:32)
    let pixels=try Pixels(crop)
    let (r,g,b)=pixels.rgb(64,16)
    #expect(r>0.99 && g<0.01 && b<0.01)
    #expect(pixels.width==128 && pixels.height==32)
    #expect(pixels.gray().count==4096)
}
