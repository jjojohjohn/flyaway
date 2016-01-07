//
//  GameScene.swift
//  Skip
//
//  Created by John Lee on 11/29/15.
//  Copyright (c) 2015 wwwww. All rights reserved.
//

import SpriteKit
import GameKit
import CoreData

enum ColliderType: UInt32 {
  case bird = 1
  case ground = 2
  case shard = 4
  case spikes = 8
  case leftWall = 16
  case rightWall = 32
}

let screenRect = UIScreen.mainScreen().bounds
let screenWidth = screenRect.size.width;
let screenHeight = screenRect.size.height;
let spikesYPositionAdjustment = CGFloat.init(floatLiteral: 5)
let birdFlyingForce = CGFloat.init(floatLiteral: 400)
let scaleFactor = screenWidth / 414.0
let startPositionYDifference = (screenHeight / 6) * scaleFactor

class JYLMainGameScene: SKScene, SKPhysicsContactDelegate {
  
  var bird = JYLBird.init()
  let spikes = JYLSpikes.init()
  var introShown = false
  let background : SKSpriteNode
  let GameStartActionString = "GameStart"
  let ShardIntroActionKey = "IntroShards"
  var tapped = false
  var gameStarted = false
  var score : Int = 0
  var stageRunner = StageRunner.init()
  let scoreLabel = SKLabelNode(fontNamed: "Dosis-SemiBold")
  let title = SKSpriteNode.init(imageNamed: "title")
  let instructions = SKSpriteNode.init(imageNamed: "instructions")
  var scoreNumberLabel = SKLabelNode(fontNamed: "Dosis-SemiBold")
  var highScoreNumberLabel = SKLabelNode(fontNamed: "Dosis-SemiBold")
  let leftIntroShard = JYLShard.init(direction: ShardDirection.left)
  let rightIntroShard = JYLShard.init(direction: ShardDirection.right)
  var managedObjectContext: NSManagedObjectContext
  let user : User

// MARK: - Overrides
  init(size : CGSize, managedObjectContext : NSManagedObjectContext) {
    let backgroundTexture = SKTexture.init(imageNamed: "background")
    self.background = SKSpriteNode.init(texture: backgroundTexture)
    self.managedObjectContext = managedObjectContext
    let player = GKLocalPlayer.localPlayer()
    let moc = self.managedObjectContext
    let userFetch = NSFetchRequest(entityName: "User")
    do {
      let result = try moc.executeFetchRequest(userFetch)
      if result.isEmpty {
        self.user = NSEntityDescription.insertNewObjectForEntityForName("User", inManagedObjectContext: self.managedObjectContext) as! User
        self.user.highScore = 0
        self.user.playerId = player.playerID
        try moc.save()
      } else {
        self.user = result.first as! User
      }
    } catch {
      fatalError("Failed to fetch user: \(error)")
    }
    super.init(size: size)
    self.physicsWorld.contactDelegate = self
  }

  required init?(coder aDecoder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
  }
  
  override func didMoveToView(view: SKView) {
    layoutGameSpriteNodes()
  }

  override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
    let location = touches.first!.locationInNode(self)
    let node = self.nodeAtPoint(location)
    if node.name == RestartButtonName {
      restart()
      Chartboost.showInterstitial(CBLocationGameOver)
    } else if node.name == ScoresButtonName{
      NSNotificationCenter.defaultCenter().postNotificationName("showGameCenter", object: nil)
    } else {
      if introShown == false {
        self.removeActionForKey(ShardIntroActionKey)
        let moveTitleUp = SKAction.moveBy(CGVectorMake(0, 400), duration: 0.5)
        let moveIntroLeftShardAnimation = SKAction.moveBy(CGVectorMake(screenWidth, 0), duration: 1.0)
        let moveIntroRightShardAnimation = SKAction.moveBy(CGVectorMake(-screenWidth, 0), duration: 1.0)
        self.title.runAction(moveTitleUp, completion: { () -> Void in
          self.title.removeFromParent()
          self.scoreLabel.hidden = false
          self.instructions.removeFromParent()
        })
        self.leftIntroShard.runAction(moveIntroLeftShardAnimation, completion: { () -> Void in
          self.leftIntroShard.removeFromParent()
        })
        self.rightIntroShard.runAction(moveIntroRightShardAnimation, completion: { () -> Void in
          self.rightIntroShard.removeFromParent()
        })
        introShown = true
      }
      if gameStarted == false {
        gameStarted = true
        bird.stopSleeping()
        let startGame = SKAction.sequence([
                          SKAction.waitForDuration(2.0),
                          SKAction.runBlock({ self.startGame() })
                        ])
        runAction(startGame)
      } else {
        if !bird.playingDead {
          let bounceVectorForce = CGVector.init(dx: 0, dy: birdFlyingForce);
          bird.physicsBody?.velocity = CGVectorMake(0, 0)
          bird.physicsBody?.applyImpulse(bounceVectorForce)
          bird.chirp()
          let turnRandom = arc4random_uniform(5)
          if turnRandom == 0 {
            bird.turn()
          }
        }
      }
    }
  }
   
  override func update(currentTime: CFTimeInterval) {
    stageRunner.checkStages()
  }
  
// MARK: - SKPhysicsContactDelegate
  func didBeginContact(contact: SKPhysicsContact) {
    var firstBody: SKPhysicsBody
    var secondBody: SKPhysicsBody
    if contact.bodyA.categoryBitMask < contact.bodyB.categoryBitMask {
      firstBody = contact.bodyA
      secondBody = contact.bodyB
    } else {
      firstBody = contact.bodyB
      secondBody = contact.bodyA
    }
    if ((firstBody.categoryBitMask & ColliderType.bird.rawValue != 0)
      && (secondBody.categoryBitMask & ColliderType.shard.rawValue != 0))
      || ((firstBody.categoryBitMask & ColliderType.bird.rawValue != 0)
      && (secondBody.categoryBitMask & ColliderType.spikes.rawValue != 0)) {
      removeActionForKey(GameStartActionString)
      gameOver()
    }
    if (firstBody.categoryBitMask & ColliderType.shard.rawValue != 0)
      && ((secondBody.categoryBitMask & ColliderType.rightWall.rawValue != 0)
      || (secondBody.categoryBitMask & ColliderType.leftWall.rawValue != 0)) {
        if firstBody.node?.parent != nil {
          firstBody.node?.removeFromParent()
          score++
          scoreLabel.text = String(score)
        }
    }
  }

// MARK - Game Logic
  func layoutGameSpriteNodes() {
    self.view!.ignoresSiblingOrder = false
    physicsWorld.gravity = CGVectorMake(0, -8)
    let ground = JYLGround.init(withWidth: screenWidth)
    let leftWall = JYLWall.init(withSide: WallSide.left)
    let rightWall = JYLWall.init(withSide: WallSide.right)
    self.addChild(leftWall)
    self.addChild(rightWall)
    self.addChild(ground)
    background.position = CGPoint(x: frame.size.width / 2, y: frame.size.height / 2)
    self.addChild(background)
    if !bird.playingDead {
      layoutTitle()
    }
    layoutScoreLabel()
    layoutWorld()
  }
  
  func layoutTitle() {
    instructions.position = CGPointMake(CGRectGetMidX(self.frame),
      CGRectGetMidY(self.frame));
    title.position = CGPointMake(CGRectGetMidX(self.frame),
      CGRectGetMidY(self.frame) * 1.55);
    self.addChild(title)
    self.addChild(instructions)
    leftIntroShard.position = CGPointMake(leftShardStart, shardMinStartHeight + (200 * scaleFactor))
    leftIntroShard.physicsBody?.collisionBitMask = 0
    leftIntroShard.physicsBody?.categoryBitMask = 0
    rightIntroShard.position = CGPointMake(rightShardStart, shardMaxStartHeight - (100 * scaleFactor))
    rightIntroShard.physicsBody?.collisionBitMask = 0
    rightIntroShard.physicsBody?.categoryBitMask = 0
    self.addChild(leftIntroShard)
    self.addChild(rightIntroShard)
    let introShards = SKAction.repeatActionForever(
      SKAction.sequence([
        SKAction.waitForDuration(5.0),
        SKAction.runBlock({
          self.leftIntroShard.position = CGPointMake(leftShardStart, shardMinStartHeight + (200 * scaleFactor))
          self.leftIntroShard.setVelocity(ShardVelocity.easyVelocity)
          self.rightIntroShard.position = CGPointMake(rightShardStart, shardMaxStartHeight - (100 * scaleFactor))
          self.rightIntroShard.setVelocity(ShardVelocity.easyVelocity)
        }),
        ])
    )
    runAction(introShards, withKey: ShardIntroActionKey)
  }
  
  func layoutScoreLabel() {
    scoreLabel.hidden = true
    scoreLabel.text = String(score)
    scoreLabel.fontSize = 65 * scaleFactor
    scoreLabel.fontColor = JYLFlyAwayColors.fontColor()
    scoreLabel.position = CGPointMake(CGRectGetMidX(self.frame),
      CGRectGetMidY(self.frame) * 1.65);
    self.addChild(scoreLabel)
    self.addChild(scoreNumberLabel)
    self.addChild(highScoreNumberLabel)
  }
  
  func layoutWorld() {
    let spikePosition = CGPointMake(self.frame.width / 2,
      self.frame.height - spikes.frame.height / 2 + spikesYPositionAdjustment)
    spikes.position = spikePosition
    self.addChild(spikes)
    bird.position = CGPointMake(self.view!.center.x,
      startPositionYDifference + (bird.size.height / 2))
    self.addChild(bird)
    let nestTexture = SKTexture.init(imageNamed: "nest")
    let birdNest = SKSpriteNode.init(texture: nestTexture)
    birdNest.setScale(scaleFactor)
    birdNest.position = CGPointMake(self.view!.center.x,
      startPositionYDifference + birdNest.size.height - (12 * scaleFactor))
    self.addChild(birdNest)
  }
  
  func gameOver() {
    let gameOverBackgroundTexture = SKTexture.init(imageNamed: "gameoverBackground")
    self.background.texture = gameOverBackgroundTexture
    bird.playDead()
    removeAllShards()
    let gapBetweenButtons = 60 * scaleFactor
    let restartButton = JYLButton.init(buttonType: ButtonType.restart)
    restartButton.position = CGPointMake(CGRectGetMidX(self.frame),
      CGRectGetMidY(self.frame) - (100 * scaleFactor))
    let shareButton = JYLButton.init(buttonType: ButtonType.share)
    shareButton.position = CGPointMake(restartButton.position.x, restartButton.position.y + gapBetweenButtons)
    let scoresButton = JYLButton.init(buttonType: ButtonType.scores)
    scoresButton.position = CGPointMake(shareButton.position.x, shareButton.position.y + gapBetweenButtons)
    let rateButton = JYLButton.init(buttonType: ButtonType.rate)
    rateButton.position = CGPointMake(scoresButton.position.x, scoresButton.position.y + gapBetweenButtons)
    let enhanceAnimation = SKAction.repeatActionForever(SKAction.sequence([
      SKAction.scaleTo(1.1, duration: 0.5),
      SKAction.scaleTo(1.0, duration: 0.5)
      ]))
    rateButton.runAction(enhanceAnimation)
    setGameOverScoreLabels()
    let leaderboardID = "HighScore"
    let sScore = GKScore(leaderboardIdentifier: leaderboardID)
    sScore.value = Int64(score)
    GKScore.reportScores([sScore], withCompletionHandler: { (error: NSError?) -> Void in
      if error != nil {
        print(error!.localizedDescription)
      } else {
        print("Score submitted")
        
      }
    })
    self.addChild(restartButton)
    self.addChild(shareButton)
    self.addChild(scoresButton)
    self.addChild(rateButton)
  }
  
  func setGameOverScoreLabels() {
    self.scoreLabel.hidden = true
    let scoreLabelTexture = SKTexture.init(imageNamed: "score")
    let highScoreLabelTexture = SKTexture.init(imageNamed: "highScore")
    let scoreLabelNode = SKSpriteNode.init(texture: scoreLabelTexture)
    let highScoreLabelNode = SKSpriteNode.init(texture: highScoreLabelTexture)
    let sidePadding = 50 * scaleFactor
    let height = (screenHeight * 0.85) / scaleFactor
    scoreLabelNode.position = CGPointMake(sidePadding + (scoreLabelNode.size.width / 2), height)
    let highScoreXPosition = screenWidth - sidePadding - (highScoreLabelNode.size.width / 2)
    highScoreLabelNode.position = CGPointMake(highScoreXPosition, height)
    self.addChild(scoreLabelNode)
    self.addChild(highScoreLabelNode)
    highScoreNumberLabel.hidden = false
    scoreNumberLabel.hidden = false
    scoreNumberLabel.fontSize = 70 * scaleFactor
    scoreNumberLabel.fontColor = JYLFlyAwayColors.fontColor()
    scoreNumberLabel.position = CGPointMake(scoreLabelNode.position.x, scoreLabelNode.position.y * 0.85 * scaleFactor)
    highScoreNumberLabel.fontSize = 70 * scaleFactor
    highScoreNumberLabel.fontColor = JYLFlyAwayColors.fontColor()
    highScoreNumberLabel.position = CGPointMake(highScoreLabelNode.position.x, highScoreLabelNode.position.y * 0.85 * scaleFactor)
    let moc = self.managedObjectContext
    var highScore = Int()
    moc.performBlockAndWait { () -> Void in
      highScore = self.user.highScore!.integerValue
      if self.score > highScore {
        self.user.highScore = self.score
        do {
          try moc.save()
        } catch {
          fatalError()
        }
      }
    }
    if highScore == 0 {
      let score = self.score
      highScoreNumberLabel.text = String(score)
    } else {
      highScoreNumberLabel.text = String(highScore)
    }
    scoreNumberLabel.text = String(self.score)
  }
  
  func removeAllShards() {
    let fadeOutAnimation = SKAction.fadeOutWithDuration(0.5)
    self.stageRunner.runAction(fadeOutAnimation) { () -> Void in
      self.stageRunner.removeFromParent()
    }
  }
  
  func startGame() {
    stageRunner = StageRunner.init()
    stageRunner.position = CGPointMake(0, 100)
    self.addChild(stageRunner)
    let gameStartAction = SKAction.repeatActionForever(
      SKAction.sequence([
        SKAction.runBlock({ self.stageRunner.runStage(self.score) }),
        SKAction.waitForDuration(0.1)
      ])
    )
    runAction(gameStartAction, withKey: GameStartActionString)
  }
  
  func restart() {
    scoreNumberLabel.hidden = true
    highScoreNumberLabel.hidden = true
    self.removeAllActions()
    self.removeAllChildren()
    gameStarted = false
    self.bird = JYLBird.init()
    self.bird.playingDead = true
    self.layoutGameSpriteNodes()
    self.bird.playingDead = false
    self.scoreLabel.hidden = false
    score = 0
    scoreLabel.text = String(score)
    let backgroundTexture = SKTexture.init(imageNamed: "background")
    self.background.texture = backgroundTexture
  }
  
}
