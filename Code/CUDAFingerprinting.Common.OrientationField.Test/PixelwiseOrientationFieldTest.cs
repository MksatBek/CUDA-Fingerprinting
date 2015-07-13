﻿using System;
using System.Text;
using System.Collections.Generic;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using CUDAFingerprinting.Common;
using CUDAFingerprinting.Common.OrientationField;
using System.Linq;
using System.Threading.Tasks;
using System.Drawing;
using System.IO;


namespace CUDAFingerprinting.Common.OrientationField.Tests
{
	[TestClass]
	public class PixelwiseOrientationFieldTest
	{
		[TestMethod]
		public void PixelwiseOrientationTest()
		{
			var image = Resources.SampleFinger;
			var bytes = ImageHelper.LoadImageAsInt(Resources.SampleFinger);

			PixelwiseOrientationField field = new PixelwiseOrientationField(bytes, 16);
			
			//double orientation = field.GetOrientation(1, 1);
			field.SaveAboveToFile(image, Path.GetTempPath() + Guid.NewGuid() + ".bmp", true);
		}
	}
}