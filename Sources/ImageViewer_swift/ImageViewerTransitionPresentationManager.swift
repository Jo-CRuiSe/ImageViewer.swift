//
//  ImageViewerTransitionPresentationManager.swift
//  ImageViewer.swift
//
//  Created by Michael Henry Pantaleon on 2020/08/19.
//

import Foundation
import UIKit

protocol ImageViewerTransitionViewControllerConvertible {
    
    // The source view
    var sourceView: UIImageView? { get }
    
    // The final view
    var targetView: UIImageView? { get }
}

final class ImageViewerTransitionPresentationAnimator:NSObject {
    
    let isPresenting: Bool
    let imageContentMode: UIView.ContentMode

    var observation: NSKeyValueObservation?
    
    init(isPresenting: Bool, imageContentMode: UIView.ContentMode) {
        self.isPresenting = isPresenting
        self.imageContentMode = imageContentMode
        super.init()
    }
}

// MARK: - UIViewControllerAnimatedTransitioning
extension ImageViewerTransitionPresentationAnimator: UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?)
        -> TimeInterval {
            return 0.3
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = isPresenting ? .to : .from
        guard let controller = transitionContext.viewController(forKey: key)
            else { return }
        
        let animationDuration = transitionDuration(using: transitionContext)
        
        if isPresenting {
            presentAnimation(
                transitionView: transitionContext.containerView,
                controller: controller,
                duration: animationDuration) { finished in
                    transitionContext.completeTransition(finished)
            }
             
        } else {
            dismissAnimation(
                transitionView: transitionContext.containerView,
                controller: controller,
                duration: animationDuration) { finished in
                    transitionContext.completeTransition(finished)
            }
        }
    }
    
    private func createDummyImageView(frame: CGRect, image:UIImage? = nil)
        -> UIImageView {
            let dummyImageView:UIImageView = UIImageView(frame: frame)
            dummyImageView.clipsToBounds = true
            dummyImageView.contentMode = imageContentMode
            dummyImageView.alpha = 1.0
            dummyImageView.image = image
            return dummyImageView
    }
    
    private func calculateAspectFitFrame(image: UIImage, in containerView: UIView) -> CGRect {
        let containerSize = containerView.bounds.size
        let imageSize = image.size
        
        guard imageSize.width > 0, imageSize.height > 0 else { return containerView.bounds }
        
        // 计算图片宽高比和容器宽高比
        let imageRatio = imageSize.width / imageSize.height
        let containerRatio = containerSize.width / containerSize.height
        
        var targetWidth: CGFloat
        var targetHeight: CGFloat
        
        if imageRatio > containerRatio {
            // 图片更宽，宽度撑满容器，高度自适应
            targetWidth = containerSize.width
            targetHeight = containerSize.width / imageRatio
        } else {
            // 图片更高，高度撑满容器，宽度自适应
            targetHeight = containerSize.height
            targetWidth = containerSize.height * imageRatio
        }
        
        // 居中计算 Origin
        let x = (containerSize.width - targetWidth) / 2
        let y = (containerSize.height - targetHeight) / 2
        
        return CGRect(x: x, y: y, width: targetWidth, height: targetHeight)
    }
    
    // MARK: - Animation Methods
    
    private func presentAnimation(
        transitionView: UIView,
        controller: UIViewController,
        duration: TimeInterval,
        completed: @escaping((Bool) -> Void)) {
            
            guard
                let transitionVC = controller as? ImageViewerTransitionViewControllerConvertible,
                let sourceView = transitionVC.sourceView,
                let image = sourceView.image
            else { return }
            
            // 1. 准备初始状态
            sourceView.alpha = 0.0
            controller.view.alpha = 0.0 // 黑色背景先透明
            
            transitionView.addSubview(controller.view)
            transitionVC.targetView?.alpha = 0.0
            transitionVC.targetView?.tintColor = sourceView.tintColor
            
            // 2. 创建临时过渡视图
            // 注意：这里我们手动创建，确保 contentMode 是 .scaleAspectFill (和缩略图一致)
            let dummyImageView = UIImageView(frame: sourceView.frameRelativeToWindow())
            dummyImageView.image = image
            dummyImageView.contentMode = .scaleAspectFill // 关键：始终保持 Fill，不要改成 Fit
            dummyImageView.clipsToBounds = true
            dummyImageView.tintColor = sourceView.tintColor
            transitionView.addSubview(dummyImageView)
            
            // 3. 计算目标位置
            // 如果我们直接动画到全屏 bounds，因为是 Fill 模式，图片会被裁剪（这导致了你看到的“放大占满全屏”）
            // 所以我们要动画到“图片在全屏 Fit 下的实际位置”
            let finalFrame = calculateAspectFitFrame(image: image, in: transitionView)
            
            // 4. 执行动画
            UIView.animate(withDuration: duration, delay: 0, options: .curveEaseInOut, animations: {
                // 让 Frame 变成计算出的实际大小
                // 因为此时 Frame 的宽高比 = 图片的宽高比，且 Mode 是 Fill
                // 所以视觉效果就变成了 Fit，而且没有突变
                dummyImageView.frame = finalFrame
                
                // 背景控制器（黑色背景）淡入，填补图片周围的空白
                controller.view.alpha = 1.0
            }) { finished in
                // 动画结束，移除临时视图，显示真正的目标视图
                self.observation = transitionVC.targetView?.observe(\.image, options: [.new, .initial]) { img, change in
                    if img.image != nil {
                        transitionVC.targetView?.alpha = 1.0
                        dummyImageView.removeFromSuperview()
                        completed(finished)
                    }
                }
                // 防御性代码：如果不需要等待图片加载，直接完成
                if self.observation == nil {
                    transitionVC.targetView?.alpha = 1.0
                    dummyImageView.removeFromSuperview()
                    completed(finished)
                }
            }
        }
    
       /// 执行关闭动画：从全屏缩小回缩略图
    /// 动画流程：
    /// 1. 创建临时图片视图，位置和大小与目标视图（全屏）相同
    /// 2. 隐藏目标视图
    /// 3. 执行动画：临时视图缩小回源视图的位置（或淡出消失）
    /// 4. 动画完成后，恢复源视图的显示并移除目标视图控制器
    private func dismissAnimation(
        transitionView: UIView,
        controller: UIViewController,
        duration: TimeInterval,
        completed: @escaping((Bool) -> Void)) {
        
        guard
            let transitionVC = controller as? ImageViewerTransitionViewControllerConvertible,
            let targetView = transitionVC.targetView,
            let image = targetView.image
        else { return }
        
        let sourceView = transitionVC.sourceView
        
        // 1. 准备初始状态（关键修改）
        
        // 获取 targetView 当前在 transitionView 坐标系中的位置
        // 这包含了一切拖拽、平移、缩放后的状态
        let currentTargetFrame = targetView.convert(targetView.bounds, to: transitionView)
        
        // 计算图片在这个 frame 里的实际显示区域 (即 AspectFit 后的 Rect)
        // 即使 targetView 很大且有黑边，这个计算能帮我们拿到图片实际的像素区域
        let startFrame = calculateVisibleImageFrame(image: image, insideRect: currentTargetFrame)
        
        // 2. 创建临时视图
        let dummyImageView = UIImageView(frame: startFrame)
        dummyImageView.image = image
        dummyImageView.contentMode = .scaleAspectFill // 保持 Fill，确保动画平滑
        dummyImageView.clipsToBounds = true
        dummyImageView.tintColor = targetView.tintColor
        // 如果有圆角需求：dummyImageView.layer.cornerRadius = sourceView?.layer.cornerRadius ?? 0
        
        transitionView.addSubview(dummyImageView)
        
        // 隐藏真实视图
        targetView.isHidden = true
        controller.view.alpha = 1.0 // 此时背景可能已经是半透明的（如果你在拖拽过程中改变了透明度）
        
        // 3. 执行动画
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseInOut, animations: {
            
            if let sourceView = sourceView {
                // 目标：缩略图的位置
                dummyImageView.frame = sourceView.frameRelativeToWindow()
            } else {
                // 异常兜底：如果没有缩略图，就原地消失
                dummyImageView.alpha = 0.0
                dummyImageView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            }
            
            // 背景完全透明
            controller.view.alpha = 0.0
            
        }) { finished in
            // 4. 清理
            sourceView?.alpha = 1.0
            dummyImageView.removeFromSuperview()
            controller.view.removeFromSuperview()
            completed(finished)
        }
    }
}

final class ImageViewerTransitionPresentationController: UIPresentationController {
    
    override var frameOfPresentedViewInContainerView: CGRect {
        var frame: CGRect = .zero
        frame.size = size(forChildContentContainer: presentedViewController,
                          withParentContainerSize: containerView!.bounds.size)
        return frame
    }
    
    override func containerViewWillLayoutSubviews() {
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

final class ImageViewerTransitionPresentationManager: NSObject {
    private let imageContentMode: UIView.ContentMode
    
    public init(imageContentMode: UIView.ContentMode) {
        self.imageContentMode = imageContentMode
    }
    
}

// MARK: - UIViewControllerTransitioningDelegate
extension ImageViewerTransitionPresentationManager: UIViewControllerTransitioningDelegate {
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        let presentationController = ImageViewerTransitionPresentationController(
            presentedViewController: presented,
            presenting: presenting)
        return presentationController
    }
    
    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
 
        return ImageViewerTransitionPresentationAnimator(isPresenting: true, imageContentMode: imageContentMode)
    }
    
    func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        return ImageViewerTransitionPresentationAnimator(isPresenting: false, imageContentMode: imageContentMode)
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate
extension ImageViewerTransitionPresentationManager: UIAdaptivePresentationControllerDelegate {
    
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
    
    func presentationController(
        _ controller: UIPresentationController,
        viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle
    ) -> UIViewController? {
        return nil
    }
}
