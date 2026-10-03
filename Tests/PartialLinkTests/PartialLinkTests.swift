import Testing
import SlideCore
import SlidePPTX

@Test func independentProductsHaveSameFacade() throws { let codecs = CodecSet([.pptx]); var slide = Slide(); slide.addText("Separate modules",frame:.init(x:10,y:10,width:400,height:80)); let result = try codecs.write(Presentation(slides:[slide])); #expect(try codecs.read(result.data).presentation.plainText == "Separate modules") }
