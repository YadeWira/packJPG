This directory contains the following:

1.  The contents of the Kodak Photo CD Photo Sampler.  This includes:
    (a) INFO.PCD --- ???
    (b) OVERVIEW.PCD --- ???
    (c) STARTUP.PCD --- ???
    (d) IMAGES --- the original PCD test images
    (e) RIGHTS --- the statement of copyrights for the images

2.  Various conversions of the PCD images:
    (a) BMP_IMAGES --- from
        http://scien.stanford.edu/pages/labsite/scien_test_images_videos.php
        These images were probably converted from PCD by Photoshop.
    (b) D65_TIFF_IMAGES --- converted by the program pcdtoppm
        http://sourceforge.net/projects/pcdtoppm/
        with a D65 white point, then converted to TIFF using pnmtotiff
    (c) D65_GREY_TIFF_IMAGES --- converted by pcdtoppm with D65 white point
        and greyscale output

What this directory does *not* contain:

3. Old TIFF conversions of the PCD images, converted by Photoshop.  When
the old TIFF conversions and the BMP files from Stanford are both converted
to PPM files and compared pixel by pixel, each RGB component differs by
at most 1 value out of 256.  This is why I say that the BMP_IMAGES were
probably converted by Photoshop.

Well, actually the old TIFF conversions are still here, at

http://www.math.purdue.edu/~lucier/PHOTO_CD/.TIFF_IMAGES/

but I do not recommend using the .TIFF_IMAGES or BMP_IMAGES.

Why?  It is true that the BMP images are brighter and more saturated than the
D65_TIFF_IMAGES, which makes them look more dramatic (having more "punch")
than the D65_TIFF_IMAGES.

On the other hand, I believe that the BMP images are (a) oversaturated and
(b) washed out because of the added brightness.  Details are lost, and I
don't think they are optimal for image processing tests.

So I would recommend using the D65_TIFF_IMAGES for image processing tests.

Brad Lucier
http://www.math.purdue.edu/~lucier/
